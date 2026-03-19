# Stella — AI Meeting Agent

Stella is an AI meeting agent that joins Google Meet calls as a voice participant. She listens, speaks, and answers questions using a knowledge base — replacing passive notetakers with an active team member.

## Quick Start

```bash
# 1. Run the setup wizard
./setup.sh

# 2. Start Stella
docker compose up --build
```

The wizard walks you through three steps: OpenAI API key, Google integration level, and knowledge base (RAG) mode. It generates `stella-data/config/stella.toml` and `docker-compose.yml` — ready to go.

Re-run `./setup.sh` any time to change settings. Your previous inputs are preserved as defaults, so you only need to override what you want to change.

## Configuration

The wizard is the easiest way to configure Stella, but you can also edit `stella-data/config/stella.toml` directly. See `stella-data/config/stella.toml.example` for the full reference with every field documented.

Run `stella validate` to check your current configuration status:
```bash
docker compose exec stella stella validate
```

## Commands

All commands can be run inside the container:
```bash
# While the daemon is running:
docker compose exec stella stella <command>

# Without the daemon (fast, no Chrome startup):
docker compose run stella stella <command>
```

### Meetings

| Command | Description |
|---------|-------------|
| `stella meet join [flags] <url>` | Join an existing Google Meet call |
| `stella meet create [flags]` | Create a new meeting and join it |

Both commands accept flags for voice, language, context, and participant hints. Run `stella meet join --help` for details.

### RAG (Knowledge Base)

| Command | Description |
|---------|-------------|
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
| RAG not starting | Run `./setup.sh` and enable the knowledge base |
