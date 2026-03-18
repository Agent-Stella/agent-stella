#!/bin/bash
# =============================================================================
# stella container entrypoint
# Starts Xvfb, PipeWire, Chrome (with auto-login), then stella daemon
# =============================================================================

set -e

# ---- Fast path for CLI commands (no Chrome/PipeWire needed) -----------------
# If arguments are passed (docker compose run stella stella rag init --write),
# skip the full startup and just exec the command directly.
if [ $# -gt 0 ]; then
    exec "$@"
fi

PROFILE="/app/data/chrome-profile"
PORT=18800
LOG_DIR="/app/data/logs"

# ---- Detect build environment -----------------------------------------------
BUILD_ENV="$(stella build-env 2>/dev/null || echo devel)"

# ---- Export config values as env vars (for Python login script) -------------
eval "$(stella export-env 2>/dev/null)"

# ---- Create data directories ------------------------------------------------
mkdir -p /app/data/{logs,credentials,chrome-profile,config,cache,backup}


# ---- Tell stella to log directly to the volume -------------------------
export STELLA_LOG_DIR="$LOG_DIR"

# ---- Set XDG_RUNTIME_DIR (required by PipeWire) ----------------------------
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# ---- Clean stale PID files from previous container runs --------------------
rm -f /tmp/stella-*.pid

# ---- Progress helpers -------------------------------------------------------
# In dist mode: single quiet line. In devel mode: step-by-step.
step() {
    if [ "$BUILD_ENV" = "devel" ]; then
        echo "  ... $1"
    fi
}

step_ok() {
    if [ "$BUILD_ENV" = "devel" ]; then
        echo "  [ok] $1"
    fi
}

step_fail() {
    # Always show failures
    echo "  [FAIL] $1"
}

if [ "$BUILD_ENV" = "dist" ]; then
    echo "Starting Stella..."
fi

# ---- Start Xvfb (virtual framebuffer) ---------------------------------------
step "Starting display server"
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > "$LOG_DIR/xvfb.log" 2>&1 &
export DISPLAY=:99
sleep 2

if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    step_fail "Display server failed to start"
    exit 1
fi
step_ok "Display server ready"

# ---- Start D-Bus (required by PipeWire) -------------------------------------
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
fi
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# ---- Start PipeWire + WirePlumber -------------------------------------------
step "Starting audio system"
pipewire > "$LOG_DIR/pipewire.log" 2>&1 &
sleep 1
wireplumber > "$LOG_DIR/wireplumber.log" 2>&1 &
sleep 1
pipewire-pulse > "$LOG_DIR/pipewire-pulse.log" 2>&1 &
sleep 2

# Create virtual sinks for audio routing
pactl load-module module-null-sink sink_name=meet_to_stella sink_properties=device.description=meet_to_stella > /dev/null 2>&1 || true
pactl load-module module-null-sink sink_name=stella_to_meet sink_properties=device.description=stella_to_meet > /dev/null 2>&1 || true
pactl load-module module-remap-source source_name=stella_mic master=stella_to_meet.monitor source_properties=device.description=stella_mic > /dev/null 2>&1 || true
pactl set-default-sink meet_to_stella 2>/dev/null
pactl set-default-source stella_mic 2>/dev/null
step_ok "Audio system ready"

# ---- Kill stale Chrome -------------------------------------------------------
pkill -f "google-chrome.*$PORT" 2>/dev/null || true
sleep 1
rm -f "$PROFILE/SingletonLock" "$PROFILE/SingletonSocket" 2>/dev/null || true

# ---- Start Chrome ------------------------------------------------------------
step "Starting Chrome"
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
sleep 5

if ! curl -s http://127.0.0.1:$PORT/json/version > /dev/null; then
    step_fail "Chrome failed to start (see $LOG_DIR/chrome.log)"
    exit 1
fi
step_ok "Chrome ready (port $PORT)"

# ---- Auto-login to Google account -------------------------------------------
if [ -n "$GOOGLE_EMAIL" ] && [ -n "$GOOGLE_PASSWORD" ]; then
    step "Logging into Google account"
    python3 << 'PYEOF' > "$LOG_DIR/google-login.log" 2>&1
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
    await ws.send(json.dumps({'id': msg_id, 'method': 'Runtime.evaluate', 'params': {'expression': expr}}))
    r = json.loads(await ws.recv())
    return r.get('result', {}).get('result', {}).get('value', '')

async def cdp_nav(ws, url, msg_id=99):
    await ws.send(json.dumps({'id': msg_id, 'method': 'Page.navigate', 'params': {'url': url}}))
    await ws.recv()

async def get_url(ws):
    return await cdp_eval(ws, 'window.location.href')

async def click_button(ws, pattern):
    return await cdp_eval(ws, f"""
(function(){{
    var b = Array.from(document.querySelectorAll('button, [role=button]'));
    var m = b.find(function(x){{ return {pattern}.test(x.innerText); }});
    if(m){{ m.click(); return 'ok'; }}
    return 'not_found';
}})()""")

async def fill_input(ws, selector, value):
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
        await cdp_nav(ws, 'https://meet.google.com')
        await asyncio.sleep(4)
        url = await get_url(ws)

        if 'meet.google.com' in url and 'workspace.google.com' not in url and 'accounts.google.com' not in url:
            print('Already logged in')
            return

        print('Login required, proceeding...')
        await cdp_nav(ws, 'https://accounts.google.com/ServiceLogin?continue=https://meet.google.com')
        await asyncio.sleep(4)
        url = await get_url(ws)

        if 'accountchooser' in url or 'signinchooser' in url:
            print('Account chooser detected')
            result = await cdp_eval(ws, f"""
(function(){{
    var items = document.querySelectorAll('[data-email]');
    for(var i=0; i<items.length; i++){{
        if(items[i].getAttribute('data-email').toLowerCase() === '{EMAIL}'.toLowerCase()){{
            items[i].click();
            return 'selected:' + items[i].getAttribute('data-email');
        }}
    }}
    var divs = document.querySelectorAll('[data-identifier]');
    for(var i=0; i<divs.length; i++){{
        if(divs[i].getAttribute('data-identifier').toLowerCase() === '{EMAIL}'.toLowerCase()){{
            divs[i].click();
            return 'selected:' + divs[i].getAttribute('data-identifier');
        }}
    }}
    var all = document.querySelectorAll('li, div[role=link], div[tabindex]');
    for(var i=0; i<all.length; i++){{
        if(all[i].textContent.includes('{EMAIL}')){{
            all[i].click();
            return 'selected_by_text';
        }}
    }}
    return 'not_found';
}})()""")

            if result == 'not_found':
                r = await click_button(ws, r'/use another|usar otra|add.*account|añadir/i')
                await asyncio.sleep(3)
                r = await fill_input(ws, 'input[type=email]', EMAIL)
                await asyncio.sleep(1)
                r = await click_button(ws, r'/next|siguiente/i')
                await asyncio.sleep(3)
            else:
                await asyncio.sleep(3)
        else:
            r = await fill_input(ws, 'input[type=email]', EMAIL)
            await asyncio.sleep(1)
            r = await click_button(ws, r'/next|siguiente/i')
            await asyncio.sleep(3)

        url = await get_url(ws)
        r = await fill_input(ws, 'input[type=password]', PWD)
        if r == 'not_found':
            r = await fill_input(ws, 'input[name=Passwd]', PWD)
        await asyncio.sleep(1)
        r = await click_button(ws, r'/next|siguiente|sign.in|iniciar/i')
        await asyncio.sleep(5)

        if TOTP_SECRET:
            url = await get_url(ws)
            if 'challenge' in url or 'signin' in url:
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
    var inp = document.querySelector('input#totpPin, input[name=totpPin], input[type=tel]');
    if(inp) return 'already_on_totp';
    return 'no_totp_option';
})()""")

                if r == 'selected_totp':
                    await asyncio.sleep(3)

                code = totp_code(TOTP_SECRET)
                r = await fill_input(ws, 'input#totpPin', code)
                if r == 'not_found':
                    r = await fill_input(ws, 'input[name=totpPin]', code)
                if r == 'not_found':
                    r = await fill_input(ws, 'input[type=tel]', code)
                await asyncio.sleep(1)
                r = await click_button(ws, r'/next|siguiente|verify|verificar/i')
                await asyncio.sleep(5)

        await cdp_nav(ws, 'https://meet.google.com')
        await asyncio.sleep(4)
        url = await get_url(ws)
        if 'meet.google.com' in url and 'workspace.google.com' not in url:
            print('Login verified OK')
        else:
            print('WARNING: login may have failed')

asyncio.run(login())
PYEOF
    if [ $? -eq 0 ]; then
        step_ok "Google login complete"
    else
        step_fail "Google login failed (see $LOG_DIR/google-login.log)"
    fi
fi

# ---- Daemon startup message (dist mode) ------------------------------------
if [ "$BUILD_ENV" = "dist" ]; then
    echo "  Starting daemon..."
fi

# ---- Start stella daemon ----------------------------------------------------
exec /usr/local/bin/stella daemon
