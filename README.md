# Stella — AI Meeting Agent

Stella is an AI meeting agent that joins Google Meet calls as a voice participant. She listens, speaks, and answers questions using a knowledge base — replacing passive notetakers with an active team member.

## Quick Start

```bash
# 1. Copy the example config and fill in your OpenAI key + Google credentials
cp stella-data/config/stella.toml.example stella-data/config/stella.toml
# Edit stella.toml with your credentials

# 2. Start Stella
docker compose up --build

# 3. (Optional) Enable the knowledge base
docker compose run stella stella rag init --write
docker compose --profile rag up --build
```

## Configuration

All settings live in `stella.toml`. The minimum configuration tiers are:

| Tier | What it enables | Required settings |
|------|----------------|-------------------|
| **Minimal** | Join meetings via CLI | `[basic] openai_api_key` |
| **+ Chrome login** | Auto-login to Google | `[basic] google_password, totp_secret` |
| **+ Calendar** | Auto-join from calendar | `[basic] google_email` + `[calendar] credentials_file` |
| **+ Email** | Ingest meeting transcripts | `[basic] app_password` |
| **+ Knowledge base** | RAG search, peer memory | `stella rag init --write` |

Full reference: `stella-data/config/stella.toml.example` (every field documented).

Run `stella validate` to check your configuration status:
```bash
docker compose exec stella stella validate
```

## Commands

All commands can be run inside the container:
```bash
docker compose exec stella stella <command>

# For commands that don't need the daemon running:
docker compose run stella stella <command>
```

### Services

| Command | Description |
|---------|-------------|
| `stella daemon [--no-rag]` | Run the meeting agent (+ embedded RAG if configured) |

### Meetings

| Command | Description |
|---------|-------------|
| `stella meet join [flags] <url>` | Join a Google Meet call |
| `stella meet create [flags]` | Create a new meeting and join it |

### Calendar

| Command | Description |
|---------|-------------|
| `stella calendar check` | Show pending calendar events |
| `stella calendar accept <event-id>` | Accept a calendar invitation |
| `stella calendar reject <event-id>` | Decline a calendar invitation |

### Email

| Command | Description |
|---------|-------------|
| `stella email check` | Scan inbox for meeting transcriptions |

### RAG (Knowledge Base)

| Command | Description |
|---------|-------------|
| `stella rag init [--write]` | Enable RAG (generates API key, writes config) |
| `stella rag remove` | Disable RAG (removes config) |
| `stella rag search <query>` | Search the knowledge base |
| `stella rag document list\|ingest\|update\|delete` | Manage documents |
| `stella rag peer list\|show\|create\|update\|delete` | Manage peer profiles |
| `stella rag meeting list\|show\|create\|update\|delete` | Manage meeting records |
| `stella rag migrate` | Run database migrations |
| `stella rag serve [port]` | Start RAG server standalone (default: 8080) |

### Tools

| Command | Description |
|---------|-------------|
| `stella backup dump\|restore\|list` | Database backup and restore |
| `stella upgrade check\|apply` | Check for and install updates |
| `stella validate` | Check configuration and print status |
| `stella version` | Print version |
| `stella screenshot` | Debug: screenshot current Chrome tab |

## Architecture

Single binary with an embedded RAG server:
- **daemon** — joins meetings, scans calendar, monitors email, runs RAG server
- **CLI** — manage documents, peers, meetings, backups

The daemon automatically starts the RAG knowledge base server when `[rag.database]` is configured (via `stella rag init --write`). Use `stella daemon --no-rag` to skip it.

Inside the Docker container:
- **Xvfb** provides a virtual display (:99)
- **PipeWire** routes audio between Chrome and the OpenAI Realtime API
- **Chrome** runs with CDP on port 18800, auto-logged into the Google account
- **stella daemon** orchestrates everything

## Docker

```bash
# Start Stella (no knowledge base)
docker compose up --build

# Start with RAG knowledge base (includes PostgreSQL)
docker compose --profile rag up --build

# Run CLI commands
docker compose exec stella stella calendar check
docker compose exec stella stella screenshot

# Run commands without the daemon (fast, no Chrome startup)
docker compose run stella stella rag init --write
docker compose run stella stella validate
```

## Enabling / Disabling RAG

```bash
# Enable: generates config and API key
docker compose run stella stella rag init --write
# Restart with postgres
docker compose --profile rag up --build

# Disable: removes [rag] section from config
docker compose run stella stella rag remove
# Restart without postgres
docker compose up
```

## Building

```bash
# Dev build (native platform only)
./src/build.sh --env devel

# Release build (all platforms: linux/amd64, linux/arm64, darwin/amd64, darwin/arm64)
./src/build.sh --env dist --all-arch
```

Output goes to `agent-stella/bin/stella-{os}-{arch}`.

## Prerequisites

- Docker and Docker Compose
- OpenAI API key (with Realtime API access)
- Google Workspace account dedicated to the agent
- Google Cloud project with Calendar, Meet, and Drive APIs enabled

## Google Workspace Setup

1. Create a dedicated Google Workspace user (e.g., `stella@yourdomain.com`)
2. Enable 2-Step Verification and save the TOTP secret
3. Create a Google Cloud project with Calendar, Meet, and Drive APIs
4. Create a service account with domain-wide delegation
5. Grant these scopes:
   - `https://www.googleapis.com/auth/calendar.events`
   - `https://www.googleapis.com/auth/meetings.space.created`
   - `https://www.googleapis.com/auth/drive.readonly`

## stella-data Directory

```
stella-data/
├── config/               # stella.toml configuration
├── logs/                 # Stella and Chrome logs
├── credentials/          # Service account JSON
├── chrome-profile/       # Chrome user data (persists login)
├── backup/               # Database backups
└── cache/                # Notification dedup cache
```

## Troubleshooting

```bash
docker compose exec stella stella validate      # Check config
docker compose exec stella stella screenshot    # See what Chrome sees
```

Logs: `stella-data/logs/`

| Problem | Check |
|---------|-------|
| Chrome crashes | Ensure `shm_size: 2gb` in docker-compose.yml |
| Audio not working | `docker compose exec stella pactl list sinks short` |
| Calendar not polling | Verify `credentials_file` + `google_email` in stella.toml |
| Google login fails | Check `stella-data/logs/google-login.log`, verify `google_password` + `totp_secret` |
| RAG not starting | Run `stella rag init --write`, restart with `--profile rag` |
