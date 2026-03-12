# agent-stella

Self-contained Docker package for **Stella**, an AI meeting agent that joins Google Meet calls as a voice participant.

The container runs `stella-meet daemon` with Chrome, PipeWire, and ffmpeg — everything needed to autonomously join meetings, listen, and speak via the OpenAI Realtime API.

## Prerequisites

- Docker and Docker Compose
- OpenAI API key (with Realtime API access)
- Google Workspace account for the agent
- (Optional) Google app password for calendar and email integration

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your credentials

# 2. Build and run
docker compose up --build
```

The daemon starts with a 1-minute heartbeat. If an app password is configured, it scans for upcoming meetings every 5 minutes (configurable via `STELLA_CALENDAR_INTERVAL`) and checks for transcription emails every 10 minutes (configurable via `STELLA_EMAIL_INTERVAL`).

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OPENAI_API_KEY` | Yes | — | OpenAI API key for Realtime voice API |
| `GOOGLE_EMAIL` | Yes | — | Google account email for Chrome auto-login |
| `GOOGLE_PASSWORD` | Yes | — | Google account password |
| `GOOGLE_APP_PASSWORD` | No | — | Google app password (enables calendar + email) |
| `GOOGLE_CALENDAR_ID` | No | `primary` | Google Calendar ID to monitor |
| `STELLA_EMAIL_SENDERS` | No | otter, fireflies, google | Comma-separated notetaker email senders to watch |
| `AGENT_OWNER_NAME` | No | — | Owner name (used in notification emails) |
| `AGENT_OWNER_EMAIL` | No | — | Owner email (enables new-meeting notifications) |
| `STELLA_RAG_URL` | No | `http://localhost:8000` | stella-rag server URL |
| `STELLA_RAG_KEY` | No | — | stella-rag API key |
| `STELLA_CALENDAR_INTERVAL` | No | `5` | Calendar scan interval in minutes |
| `STELLA_EMAIL_INTERVAL` | No | `10` | Email scan interval in minutes |
| `STELLA_DEFAULT_VOICE` | No | `coral` | OpenAI voice (alloy, ash, ballad, coral, echo, sage, shimmer, verse) |
| `STELLA_DEFAULT_LANG` | No | `español` | Response language |
| `CHROME_DEBUG_ADDR` | No | `http://127.0.0.1:18800` | Chrome CDP address (internal) |

## stella-data Directory

The `stella-data/` directory is bind-mounted into the container at `/app/data`. Subdirectories are auto-created on first run:

```
stella-data/
├── logs/                 # stella-meet and Chrome logs
├── chrome-profile/       # Chrome user data (persists login session)
└── briefing.json         # Optional meeting briefing
```

## Google App Password Setup

To enable autonomous calendar and email scanning:

1. Enable **2-Step Verification** on the Google account (required for app passwords)
2. Go to https://myaccount.google.com/apppasswords
3. Create an app password (name it "Stella" or similar)
4. Paste the 16-character password into `.env` as `GOOGLE_APP_PASSWORD`

That's it — no GCP project, no service account, no domain delegation needed.

**Calendar ID** (optional): defaults to `primary` (the account's main calendar). To use a different calendar: Google Calendar → Settings (gear icon) → click the calendar name → "Integrate calendar" section → copy the Calendar ID (looks like `abc123@group.calendar.google.com`).

**Email senders** (optional): by default, Stella watches for emails from Otter.ai, Fireflies.ai, and Google Meet recordings. Set `STELLA_EMAIL_SENDERS` to a comma-separated list of sender addresses to customize.

## Architecture

Inside the container:

- **Xvfb** provides a virtual display (:99) — Google Meet requires a display even in headless operation
- **PipeWire** runs with two virtual audio sinks:
  - `meet_to_igor` — captures Chrome/Meet audio (what participants say)
  - `igor_to_meet` — plays agent audio back into Chrome (what Stella says)
- **Chrome** runs with remote debugging (CDP) on port 18800, auto-logged into the Google account
- **stella-meet daemon** orchestrates everything: polls calendar, joins meetings via CDP, streams audio to/from the OpenAI Realtime API

## Troubleshooting

**Chrome crashes immediately**
- Ensure `shm_size: 2gb` is set in docker-compose.yml (default 64MB is too small for Chrome)
- Check `stella-data/logs/chrome.log`

**Audio not working in meetings**
- Verify PipeWire started: `docker exec agent-stella pw-cli ls Node`
- Check virtual sinks exist: `docker exec agent-stella pactl list sinks short`

**Calendar not polling**
- Ensure `GOOGLE_EMAIL` and `GOOGLE_APP_PASSWORD` are both set
- Verify the app password is correct (16 characters, no spaces)
- Check that 2-Step Verification is enabled on the Google account

**Container exits on startup**
- Check logs: `docker compose logs stella`
- Common cause: missing required env vars (`OPENAI_API_KEY`, `GOOGLE_EMAIL`, `GOOGLE_PASSWORD`)

**Google login fails**
- The Chrome profile persists across restarts — if login succeeded once, it won't need to log in again
- 2-Step Verification must be enabled (required for app passwords); use the app password for `GOOGLE_APP_PASSWORD`
- Check `stella-data/logs/chrome.log` for login-related errors
