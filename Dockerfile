# =============================================================================
# agent-stella — Docker image for Stella AI meeting agent
# Pre-built binary + runtime with Chrome, PipeWire, ffmpeg
# =============================================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install Chrome (amd64) or Chromium (arm64) + runtime dependencies
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
    && if [ "$TARGETARCH" = "amd64" ]; then \
        curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
          | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
        && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
           http://dl.google.com/linux/chrome/deb/ stable main" \
           > /etc/apt/sources.list.d/google-chrome.list \
        && apt-get update \
        && apt-get install -y --no-install-recommends google-chrome-stable ; \
       else \
        apt-get install -y --no-install-recommends chromium ; \
       fi \
    && apt-get install -y --no-install-recommends \
        pipewire pipewire-pulse pipewire-alsa wireplumber \
        ffmpeg pulseaudio-utils \
        python3 python3-websockets \
        xvfb dbus-x11 dbus-user-session procps \
    && rm -rf /var/lib/apt/lists/*

# Symlink chromium → google-chrome for start-chrome.sh compatibility
RUN if [ ! -f /usr/bin/google-chrome ] && [ -f /usr/bin/chromium ]; then \
        ln -s /usr/bin/chromium /usr/bin/google-chrome ; \
    fi

# Persist env vars so `docker compose exec` sessions can reach
# Xvfb, PipeWire, and D-Bus started by the entrypoint.
ENV DISPLAY=:99
ENV XDG_RUNTIME_DIR=/tmp/runtime-root

WORKDIR /app

# Copy pre-built binary (build with src/stella-meet/build.sh first)
COPY bin/stella-meet /usr/local/bin/stella-meet

# Copy entrypoint script
COPY start-chrome.sh /app/start-chrome.sh
RUN chmod +x /app/start-chrome.sh

EXPOSE 18800

ENTRYPOINT ["/app/start-chrome.sh"]
