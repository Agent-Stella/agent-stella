# Stella — AI Meeting Agent

Stella is an AI meeting agent that joins Google Meet calls as a voice participant. She listens, speaks, and answers questions using a knowledge base — replacing passive notetakers with an active team member.

## Quick Start

```bash
# 1. Copy the example config and fill in your OpenAI key
cp stella-data/config/stella.toml.example stella-data/config/stella.toml

# 2. (Optional) Enable the knowledge base
stella rag init --write

# 3. Start Stella
docker compose up --build
```

## Configuration

All settings live in `stella.toml`. The minimum configuration tiers are:

| Tier | What it enables | Required settings |
|------|----------------|-------------------|
| **Minimal** | Join meetings via CLI | `[basic] openai_api_key` |
| **+ Calendar** | Auto-join from calendar | `[basic] google_email` + `[calendar] credentials_file` |
| **+ Email** | Ingest meeting transcripts | `[basic] google_email, app_password` |
| **+ Knowledge base** | RAG search, peer memory | `[rag.database]` connection settings |

Full reference: `stella-data/config/stella.toml.example` (every field documented).

Run `stella validate` to check your configuration status.

## Commands

```
SERVICES (long-running processes)
  stella daemon [--no-rag]   Run the meeting agent (+ embedded RAG if configured)
  stella rag serve [port]    Start RAG server standalone (default: 8080)

MEETINGS
  stella meet join [flags] <meet-url>    Join a Google Meet call
  stella meet create [flags]             Create a new meeting and join it

CALENDAR
  stella calendar check                  Show pending calendar events
  stella calendar accept <event-id>      Accept a calendar invitation
  stella calendar reject <event-id>      Decline a calendar invitation

EMAIL
  stella email check         Scan inbox for meeting transcriptions

RAG MANAGEMENT
  stella rag search <query>              Search the knowledge base
  stella rag document list|ingest|update|delete
  stella rag peer list|show|create|update|delete
  stella rag meeting list|show|create|update|delete
  stella rag migrate                     Run database migrations

TOOLS
  stella backup dump|restore|list        Database backup and restore
  stella upgrade check|apply             Check for and install updates
  stella validate                        Check configuration and print status
  stella version                         Print version
```

## Architecture

Single binary, two modes:
- **daemon** — joins meetings, scans calendar, monitors email, embedded RAG server
- **CLI** — manage documents, peers, meetings, backups

The daemon automatically starts the RAG knowledge base server if `[rag.database]` is configured. Use `stella daemon --no-rag` to skip it.

Inside the Docker container:
- **Xvfb** provides a virtual display (:99)
- **PipeWire** routes audio between Chrome and the OpenAI Realtime API
- **Chrome** runs with CDP on port 18800, auto-logged into the Google account
- **stella daemon** orchestrates everything

## Docker

```bash
# Start Stella
docker compose up --build

# Run CLI commands inside the container
docker compose exec stella stella calendar check
docker compose exec stella stella screenshot
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
stella validate            # Check config
stella screenshot          # See what Chrome sees
```

Logs: `stella-data/logs/`

| Problem | Check |
|---------|-------|
| Chrome crashes | Ensure `shm_size: 2gb` in docker-compose.yml |
| Audio not working | `docker compose exec stella pactl list sinks short` |
| Calendar not polling | Verify credentials_file + google_email are set |
| Google login fails | Check `stella-data/logs/google-login.log` |
