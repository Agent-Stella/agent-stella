# agent-stella

**Stella** is an AI meeting agent that joins Google Meet calls as a voice participant. She listens, speaks, and answers questions using a knowledge base — replacing passive notetakers with an active team member.

## Features

- **Calendar management** — Monitors Google Calendar, auto-joins meetings, accepts/rejects invitations
- **Email monitoring** — Scans for meeting transcripts and notes, ingests them into the knowledge base
- **On-demand meetings** — Create ad-hoc Google Meet calls from the CLI
- **Memory & knowledge base** — RAG-powered knowledge base with hybrid search (semantic + keyword)
- **Peer trust system** — Maintains profiles for known contacts with context for each person
- **Gemini notes** — Activates Google Meet's built-in transcription when the agent is the host
- **Voice interaction** — Real-time bidirectional audio via OpenAI Realtime API

## Prerequisites

- Docker and Docker Compose
- OpenAI API key (with Realtime API access)
- Google Workspace account dedicated to the agent
- Google Cloud project with Calendar, Meet, and Drive APIs enabled

## Google Workspace & Cloud Setup

### 1. Create a Google Workspace user

Create a dedicated user in your Google Workspace admin console (e.g., `stella@yourdomain.com`). This account will be used for Chrome auto-login and as the agent's identity in meetings.

### 2. Set up TOTP for the user

Enable 2-Step Verification on the agent's Google account and add an authenticator app. Save the TOTP secret (the base32-encoded key shown during setup) — you'll need it for the `GOOGLE_TOTP_SECRET` environment variable so the container can log in automatically.

### 3. Create a Google Cloud project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (e.g., "Stella Agent")

### 4. Enable APIs

Enable the following APIs in your Google Cloud project:

- **Google Calendar API** — reading and creating calendar events
- **Google Meet REST API** — creating meetings with access settings
- **Google Drive API** — reading shared documents for knowledge base ingestion

### 5. Create a service account

1. Go to **IAM & Admin → Service Accounts**
2. Create a service account (e.g., `stella-agent@your-project.iam.gserviceaccount.com`)
3. Create a JSON key and download it
4. Place the JSON file in `stella-data/credentials/` (it will be mounted into the container)

### 6. Set up Domain-wide Delegation

1. In the Google Cloud Console, go to your service account → **Details** → note the **Client ID**
2. In Google Workspace Admin Console, go to **Security → API Controls → Domain-wide Delegation**
3. Add a new API client with the service account's Client ID and these scopes:
   - `https://www.googleapis.com/auth/calendar.events`
   - `https://www.googleapis.com/auth/meetings.space.created`
   - `https://www.googleapis.com/auth/drive.readonly`

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OPENAI_API_KEY` | Yes | — | OpenAI API key for Realtime voice API |
| `GOOGLE_EMAIL` | Yes | — | Google account email for Chrome auto-login |
| `GOOGLE_PASSWORD` | Yes | — | Google account password |
| `GOOGLE_TOTP_SECRET` | Yes* | — | TOTP secret for automated 2FA login (base32) |
| `GOOGLE_CREDENTIALS_FILE` | Yes* | — | Path to service account JSON (inside container) |
| `GOOGLE_APP_PASSWORD` | No | — | Google app password for IMAP email scanning |
| `GOOGLE_CALENDAR_ID` | No | `primary` | Google Calendar ID to monitor |
| `STELLA_AGENT_NAME` | No | `Igor` | Agent name shown in Google Meet |
| `STELLA_EMAIL_KEYWORDS` | No | `notes,transcript,...` | Comma-separated subject keywords for email scanning |
| `STELLA_ENABLE_NOTES` | No | `true` | Activate Gemini notes/transcription for daemon joins |
| `STELLA_AUTO_ACCEPT_GUESTS` | No | `true` | Auto-admit waiting guests for daemon joins |
| `AGENT_OWNER_NAME` | No | — | Owner name (used in notification emails) |
| `AGENT_OWNER_EMAIL` | No | — | Owner email (enables new-meeting notifications) |
| `STELLA_RAG_URL` | No | `http://localhost:8000` | stella-rag server URL |
| `STELLA_RAG_KEY` | No | — | stella-rag API key |
| `STELLA_CALENDAR_INTERVAL` | No | `5` | Calendar scan interval in minutes |
| `STELLA_EMAIL_INTERVAL` | No | `10` | Email scan interval in minutes |
| `STELLA_DEFAULT_VOICE` | No | `coral` | OpenAI voice (alloy, ash, ballad, coral, echo, sage, shimmer, verse) |
| `STELLA_DEFAULT_LANG` | No | `español` | Response language |
| `CHROME_DEBUG_ADDR` | No | `http://127.0.0.1:18800` | Chrome CDP address (internal) |

\* `GOOGLE_TOTP_SECRET` is required if the account has 2FA with an authenticator app. `GOOGLE_CREDENTIALS_FILE` is required for calendar integration and meeting creation.

## Running with Docker Compose

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your credentials

# 2. Place your service account JSON
mkdir -p stella-data/credentials
cp /path/to/service-account.json stella-data/credentials/

# 3. Build and run
docker compose up --build

# 4. View logs
docker compose logs -f stella

# 5. Stop
docker compose down
```

## Running Commands

You can run CLI commands inside the running container:

```bash
# Open a shell
docker compose exec stella bash

# Run commands directly
docker compose exec stella agent-stella calendar check
docker compose exec stella agent-stella screenshot
```

For the full command reference, see [doc/usage.md](doc/usage.md).

## Architecture

Inside the container:

- **Xvfb** provides a virtual display (:99) — Google Meet requires a display even in headless operation
- **PipeWire** runs with two virtual audio sinks:
  - `meet_to_stella` — captures Chrome/Meet audio (what participants say)
  - `stella_to_meet` — plays agent audio back into Chrome (what Stella says)
- **Chrome** runs with remote debugging (CDP) on port 18800, auto-logged into the Google account
- **agent-stella daemon** orchestrates everything: polls calendar, joins meetings via CDP, streams audio to/from the OpenAI Realtime API

## stella-data Directory

The `stella-data/` directory is bind-mounted into the container at `/app/data`. Subdirectories are auto-created on first run:

```
stella-data/
├── logs/                 # agent-stella and Chrome logs
├── credentials/          # Service account JSON
├── chrome-profile/       # Chrome user data (persists login session)
└── briefing.json         # Optional meeting briefing
```

## Troubleshooting

**Chrome crashes immediately**
- Ensure `shm_size: 2gb` is set in docker-compose.yml (default 64MB is too small for Chrome)
- Check `stella-data/logs/chrome.log`

**Audio not working in meetings**
- Verify PipeWire started: `docker compose exec stella pw-cli ls Node`
- Check virtual sinks exist: `docker compose exec stella pactl list sinks short`

**Calendar not polling**
- Ensure `GOOGLE_CREDENTIALS_FILE` and `GOOGLE_EMAIL` are both set
- Verify the service account has Domain-wide Delegation configured
- Check that the correct API scopes are granted

**Container exits on startup**
- Check logs: `docker compose logs stella`
- Common cause: missing required env vars (`OPENAI_API_KEY`, `GOOGLE_EMAIL`, `GOOGLE_PASSWORD`)

**Google login fails**
- The Chrome profile persists across restarts — if login succeeded once, it won't need to log in again
- Ensure `GOOGLE_TOTP_SECRET` is set if 2FA is enabled
- Check `stella-data/logs/chrome.log` for login-related errors

**Email scanning not working**
- Ensure `GOOGLE_EMAIL` and `GOOGLE_APP_PASSWORD` are both set
- Verify the app password is correct (16 characters, no spaces)
- Check that 2-Step Verification is enabled on the Google account (required for app passwords)
