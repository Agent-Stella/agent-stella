#!/bin/bash
# =============================================================================
# agent-stella container entrypoint
# Starts Xvfb, PipeWire, Chrome (with auto-login), then stella-meet daemon
# =============================================================================

set -e

PROFILE="/app/data/chrome-profile"
PORT=18800
LOG_DIR="/app/data/logs"

# ---- Create data directories ------------------------------------------------
mkdir -p /app/data/{logs,credentials,chrome-profile}

# ---- Tell stella-meet to log directly to the volume -------------------------
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

# ---- Start PipeWire ----------------------------------------------------------
echo "Starting PipeWire..."
pipewire &
sleep 1
pipewire-pulse &
sleep 2

# Create virtual sinks for audio routing
pw-cli create-node adapter '{ factory.name=support.null-audio-sink
    node.name=meet_to_igor media.class=Audio/Sink
    audio.position=[FL FR] monitor.channel-volumes=true }' 2>/dev/null || true

pw-cli create-node adapter '{ factory.name=support.null-audio-sink
    node.name=igor_to_meet media.class=Audio/Sink
    audio.position=[FL FR] monitor.channel-volumes=true }' 2>/dev/null || true

echo "PipeWire running with virtual sinks"

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
    python3 << PYEOF
import json, asyncio, websockets, urllib.request

async def login():
    tabs = json.loads(urllib.request.urlopen('http://127.0.0.1:$PORT/json').read())
    tab = next(t for t in tabs if t.get('type') == 'page')

    async with websockets.connect(tab['webSocketDebuggerUrl']) as ws:
        # Navigate to Google Meet to check session
        await ws.send(json.dumps({'id':1,'method':'Page.navigate','params':{'url':'https://meet.google.com'}}))
        await ws.recv()
        await asyncio.sleep(4)

        await ws.send(json.dumps({'id':2,'method':'Runtime.evaluate','params':{'expression':'window.location.href'}}))
        r = json.loads(await ws.recv())
        url = r['result']['result'].get('value','')
        print('URL:', url)

        if 'accounts.google.com' in url or 'signin' in url:
            print('Login required, proceeding...')
            email = '$GOOGLE_EMAIL'
            pwd = '$GOOGLE_PASSWORD'

            # Enter email
            await ws.send(json.dumps({'id':3,'method':'Runtime.evaluate','params':{'expression':f"""
(function(){{
    var inp = document.querySelector('input[type=email]');
    if(inp){{ inp.value='{email}'; inp.dispatchEvent(new Event('input',{{bubbles:true}})); return 'ok'; }}
    return 'no email field';
}})()
"""}}))
            r = json.loads(await ws.recv())
            print('email:', r['result']['result'].get('value',''))
            await asyncio.sleep(1)

            # Click Next
            await ws.send(json.dumps({'id':4,'method':'Runtime.evaluate','params':{'expression':"""
(function(){var b=Array.from(document.querySelectorAll('button'));var n=b.find(x=>/next|siguiente/i.test(x.innerText));if(n){n.click();return 'ok';}return 'no next button';})()
"""}}))
            await ws.recv()
            await asyncio.sleep(3)

            # Enter password
            await ws.send(json.dumps({'id':5,'method':'Runtime.evaluate','params':{'expression':f"""
(function(){{
    var inp = document.querySelector('input[type=password]');
    if(inp){{ inp.value='{pwd}'; inp.dispatchEvent(new Event('input',{{bubbles:true}})); return 'ok'; }}
    return 'no password field';
}})()
"""}}))
            r = json.loads(await ws.recv())
            print('pwd:', r['result']['result'].get('value',''))
            await asyncio.sleep(1)

            # Click Sign In
            await ws.send(json.dumps({'id':6,'method':'Runtime.evaluate','params':{'expression':"""
(function(){var b=Array.from(document.querySelectorAll('button'));var n=b.find(x=>/next|siguiente|sign in/i.test(x.innerText));if(n){n.click();return 'ok';}return 'no sign-in button';})()
"""}}))
            await ws.recv()
            await asyncio.sleep(5)
            print('Login submitted')
        else:
            print('Already logged in')

asyncio.run(login())
PYEOF
    echo "Google login complete"
else
    echo "GOOGLE_EMAIL/GOOGLE_PASSWORD not set, skipping auto-login"
fi

echo "Chrome ready for stella-meet"

# ---- Start stella-meet daemon ------------------------------------------------
exec /app/stella-meet daemon
