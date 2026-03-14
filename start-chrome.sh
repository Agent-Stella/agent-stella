#!/bin/bash
# =============================================================================
# agent-stella container entrypoint
# Starts Xvfb, PipeWire, Chrome (with auto-login), then agent-stella daemon
# =============================================================================

set -e

PROFILE="/app/data/chrome-profile"
PORT=18800
LOG_DIR="/app/data/logs"

# ---- Create data directories ------------------------------------------------
mkdir -p /app/data/{logs,credentials,chrome-profile}

# ---- Tell agent-stella to log directly to the volume -------------------------
export STELLA_LOG_DIR="$LOG_DIR"

# ---- Set XDG_RUNTIME_DIR (required by PipeWire) ----------------------------
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# ---- Clean stale PID files from previous container runs --------------------
rm -f /tmp/stella-*.pid

# ---- Start Xvfb (virtual framebuffer) ---------------------------------------
echo "Starting Xvfb..."
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
export DISPLAY=:99
sleep 2

# Verify display is available
if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "ERROR: Xvfb failed to start"
    exit 1
fi
echo "Xvfb running on :99"

# ---- Start D-Bus (required by PipeWire) -------------------------------------
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
fi

# ---- Start D-Bus system daemon (required by PipeWire/WirePlumber) -----------
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# ---- Start PipeWire + WirePlumber -------------------------------------------
echo "Starting PipeWire..."
pipewire > "$LOG_DIR/pipewire.log" 2>&1 &
sleep 1
wireplumber > "$LOG_DIR/wireplumber.log" 2>&1 &
sleep 1
pipewire-pulse > "$LOG_DIR/pipewire-pulse.log" 2>&1 &
sleep 2

# Create virtual sinks for audio routing
pactl load-module module-null-sink sink_name=meet_to_stella sink_properties=device.description=meet_to_stella || true
pactl load-module module-null-sink sink_name=stella_to_meet sink_properties=device.description=stella_to_meet || true

# Create a proper source from stella_to_meet's monitor so Chrome sees it as a microphone
# (Chrome won't use .monitor sources directly — needs a real named source)
pactl load-module module-remap-source source_name=stella_mic master=stella_to_meet.monitor source_properties=device.description=stella_mic || true

# Set defaults:
#   sink = meet_to_stella (Chrome audio output → captured by stella)
#   source = stella_mic (stella audio output → Chrome mic input)
pactl set-default-sink meet_to_stella
pactl set-default-source stella_mic

echo "PipeWire + WirePlumber running with virtual sinks"

# ---- Kill stale Chrome -------------------------------------------------------
pkill -f "google-chrome.*$PORT" 2>/dev/null || true
sleep 1
rm -f "$PROFILE/SingletonLock" "$PROFILE/SingletonSocket" 2>/dev/null || true

# ---- Start Chrome ------------------------------------------------------------
echo "Starting Chrome..."
nohup google-chrome \
    --remote-debugging-port=$PORT \
    --user-data-dir="$PROFILE" \
    --no-first-run \
    --no-default-browser-check \
    --disable-gpu \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-setuid-sandbox \
    --use-fake-ui-for-media-stream \
    --autoplay-policy=no-user-gesture-required \
    about:blank > "$LOG_DIR/chrome.log" 2>&1 &

CHROME_PID=$!
echo "Chrome starting (pid $CHROME_PID)..."
sleep 5

# Verify Chrome responds
if ! curl -s http://127.0.0.1:$PORT/json/version > /dev/null; then
    echo "ERROR: Chrome not responding on port $PORT"
    cat "$LOG_DIR/chrome.log"
    exit 1
fi
echo "Chrome OK on port $PORT"

# ---- Auto-login to Google account -------------------------------------------
if [ -n "$GOOGLE_EMAIL" ] && [ -n "$GOOGLE_PASSWORD" ]; then
    echo "Attempting Google auto-login..."
    python3 << 'PYEOF'
import json, asyncio, websockets, urllib.request, hmac, hashlib, struct, base64, time as _time, os

def totp_code(secret_b32):
    """Generate a 6-digit TOTP code from a base32 secret (no external deps)."""
    key = base64.b32decode(secret_b32.upper().replace(' ', ''), casefold=True)
    counter = struct.pack('>Q', int(_time.time()) // 30)
    mac = hmac.new(key, counter, hashlib.sha1).digest()
    offset = mac[-1] & 0x0F
    code = struct.unpack('>I', mac[offset:offset+4])[0] & 0x7FFFFFFF
    return str(code % 1000000).zfill(6)

EMAIL = os.environ.get('GOOGLE_EMAIL', '')
PWD = os.environ.get('GOOGLE_PASSWORD', '')
TOTP_SECRET = os.environ.get('GOOGLE_TOTP_SECRET', '')
CDP_PORT = os.environ.get('PORT', '18800')

async def cdp_eval(ws, expr, msg_id=99):
    """Evaluate JS via CDP and return the string result."""
    await ws.send(json.dumps({'id': msg_id, 'method': 'Runtime.evaluate', 'params': {'expression': expr}}))
    r = json.loads(await ws.recv())
    return r.get('result', {}).get('result', {}).get('value', '')

async def cdp_nav(ws, url, msg_id=99):
    """Navigate to a URL via CDP."""
    await ws.send(json.dumps({'id': msg_id, 'method': 'Page.navigate', 'params': {'url': url}}))
    await ws.recv()

async def get_url(ws):
    return await cdp_eval(ws, 'window.location.href')

async def click_button(ws, pattern):
    """Click the first button whose text matches the regex pattern."""
    return await cdp_eval(ws, f"""
(function(){{
    var b = Array.from(document.querySelectorAll('button, [role=button]'));
    var m = b.find(function(x){{ return {pattern}.test(x.innerText); }});
    if(m){{ m.click(); return 'ok'; }}
    return 'not_found';
}})()""")

async def fill_input(ws, selector, value):
    """Fill an input field and dispatch input event."""
    return await cdp_eval(ws, f"""
(function(){{
    var inp = document.querySelector('{selector}');
    if(inp){{
        inp.focus();
        inp.value = '{value}';
        inp.dispatchEvent(new Event('input', {{bubbles:true}}));
        inp.dispatchEvent(new Event('change', {{bubbles:true}}));
        return 'ok';
    }}
    return 'not_found';
}})()""")

async def login():
    tabs = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{CDP_PORT}/json').read())
    tab = next(t for t in tabs if t.get('type') == 'page')

    async with websockets.connect(tab['webSocketDebuggerUrl']) as ws:
        # 1. Check if already logged in
        await cdp_nav(ws, 'https://meet.google.com')
        await asyncio.sleep(4)
        url = await get_url(ws)
        print(f'Initial URL: {url}')

        if 'meet.google.com' in url and 'workspace.google.com' not in url and 'accounts.google.com' not in url:
            print('Already logged in')
            return

        print('Login required, proceeding...')

        # 2. Navigate to sign-in page
        await cdp_nav(ws, 'https://accounts.google.com/ServiceLogin?continue=https://meet.google.com')
        await asyncio.sleep(4)
        url = await get_url(ws)
        print(f'Sign-in page: {url}')

        # 3. Handle account chooser — click the target account or "Use another account"
        if 'accountchooser' in url or 'signinchooser' in url:
            print('Account chooser detected')
            # Try clicking on the target email if listed
            result = await cdp_eval(ws, f"""
(function(){{
    // Look for the account tile containing our email
    var items = document.querySelectorAll('[data-email]');
    for(var i=0; i<items.length; i++){{
        if(items[i].getAttribute('data-email').toLowerCase() === '{EMAIL}'.toLowerCase()){{
            items[i].click();
            return 'selected:' + items[i].getAttribute('data-email');
        }}
    }}
    // Also try matching by text content
    var divs = document.querySelectorAll('[data-identifier]');
    for(var i=0; i<divs.length; i++){{
        if(divs[i].getAttribute('data-identifier').toLowerCase() === '{EMAIL}'.toLowerCase()){{
            divs[i].click();
            return 'selected:' + divs[i].getAttribute('data-identifier');
        }}
    }}
    // Try clicking any element that contains the email text
    var all = document.querySelectorAll('li, div[role=link], div[tabindex]');
    for(var i=0; i<all.length; i++){{
        if(all[i].textContent.includes('{EMAIL}')){{
            all[i].click();
            return 'selected_by_text';
        }}
    }}
    return 'not_found';
}})()""")
            print(f'Account selection: {result}')

            if result == 'not_found':
                # Click "Use another account" / "Usar otra cuenta"
                r = await click_button(ws, r'/use another|usar otra|add.*account|añadir/i')
                print(f'Use another account: {r}')
                await asyncio.sleep(3)
                # Now fill email
                r = await fill_input(ws, 'input[type=email]', EMAIL)
                print(f'Email fill: {r}')
                await asyncio.sleep(1)
                r = await click_button(ws, r'/next|siguiente/i')
                print(f'Email next: {r}')
                await asyncio.sleep(3)
            else:
                # Account was selected, should go to password page
                await asyncio.sleep(3)

        else:
            # 4. Standard email entry (no account chooser)
            r = await fill_input(ws, 'input[type=email]', EMAIL)
            print(f'Email fill: {r}')
            await asyncio.sleep(1)
            r = await click_button(ws, r'/next|siguiente/i')
            print(f'Email next: {r}')
            await asyncio.sleep(3)

        # 5. Password page
        url = await get_url(ws)
        print(f'Password page: {url}')
        r = await fill_input(ws, 'input[type=password]', PWD)
        print(f'Password fill: {r}')
        if r == 'not_found':
            # Password field might be name="Passwd" on some flows
            r = await fill_input(ws, 'input[name=Passwd]', PWD)
            print(f'Password fill (Passwd): {r}')
        await asyncio.sleep(1)
        r = await click_button(ws, r'/next|siguiente|sign.in|iniciar/i')
        print(f'Password submit: {r}')
        await asyncio.sleep(5)

        # 6. TOTP / MFA challenge
        if TOTP_SECRET:
            url = await get_url(ws)
            print(f'Post-password URL: {url}')

            if 'challenge' in url or 'signin' in url:
                # Google might show an MFA method chooser. Try to select TOTP.
                # Look for "Google Authenticator" / "authentication app" option
                r = await cdp_eval(ws, """
(function(){
    var items = document.querySelectorAll('[data-challengetype], [data-sendmethod]');
    for(var i=0; i<items.length; i++){
        var t = items[i].textContent.toLowerCase();
        if(t.includes('authenticator') || t.includes('autenticador') || t.includes('verification code') || t.includes('código de verificación')){
            items[i].click();
            return 'selected_totp';
        }
    }
    // Check if we're already on the TOTP input page
    var inp = document.querySelector('input#totpPin, input[name=totpPin], input[type=tel]');
    if(inp) return 'already_on_totp';
    return 'no_totp_option';
})()""")
                print(f'MFA method: {r}')

                if r == 'selected_totp':
                    await asyncio.sleep(3)

                code = totp_code(TOTP_SECRET)
                print(f'Entering TOTP code: {code[:2]}****')

                r = await fill_input(ws, 'input#totpPin', code)
                if r == 'not_found':
                    r = await fill_input(ws, 'input[name=totpPin]', code)
                if r == 'not_found':
                    r = await fill_input(ws, 'input[type=tel]', code)
                print(f'TOTP fill: {r}')
                await asyncio.sleep(1)

                r = await click_button(ws, r'/next|siguiente|verify|verificar/i')
                print(f'TOTP submit: {r}')
                await asyncio.sleep(5)
            else:
                print('No MFA challenge detected')

        # 7. Verify login
        await cdp_nav(ws, 'https://meet.google.com')
        await asyncio.sleep(4)
        url = await get_url(ws)
        print(f'Post-login URL: {url}')
        if 'meet.google.com' in url and 'workspace.google.com' not in url:
            print('Login verified OK')
        else:
            print('WARNING: login may have failed — Chrome may not be authenticated')

asyncio.run(login())
PYEOF
    echo "Google login complete"
else
    echo "GOOGLE_EMAIL/GOOGLE_PASSWORD not set, skipping auto-login"
fi

echo "Chrome ready for agent-stella"

# ---- Start agent-stella daemon ------------------------------------------------
exec /usr/local/bin/agent-stella daemon
