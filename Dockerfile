# =============================================================================
# agent-stella — Docker image for Stella AI meeting agent
# Multi-stage build: Go binary + runtime with Chrome, PipeWire, ffmpeg
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Build stella-meet Go binary
# ---------------------------------------------------------------------------
FROM golang:1.22-bookworm AS builder

WORKDIR /build
COPY src/stella-meet/ .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /stella-meet .

# ---------------------------------------------------------------------------
# Stage 2: Runtime
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Google Chrome APT repo
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
    && curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
       | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
       http://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list

# Install all runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        google-chrome-stable \
        pipewire pipewire-pulse pipewire-alsa \
        ffmpeg \
        pulseaudio-utils \
        python3 python3-websockets \
        xvfb \
        dbus-x11 \
        procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from build stage
COPY --from=builder /stella-meet /app/stella-meet

# Copy entrypoint script
COPY agent-stella/start-chrome.sh /app/start-chrome.sh
RUN chmod +x /app/start-chrome.sh

EXPOSE 18800

ENTRYPOINT ["/app/start-chrome.sh"]
