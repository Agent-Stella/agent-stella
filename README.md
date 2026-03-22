# Stella — AI Meeting Agent

Stella is an AI meeting agent that joins Google Meet calls as a voice participant. She listens, speaks, and answers questions using a knowledge base — replacing passive notetakers with an active team member.

## Prerequisites

- **Docker** and **Docker Compose**
- An **OpenAI API key** with Realtime API access
- A **Google Workspace** account dedicated to the agent (basic Gmail is not supported)
- A **Google Cloud project** with Calendar, Meet, and Drive APIs enabled
- A **service account** with domain-wide delegation

Stella requires Google Workspace because it uses the **Meet REST API** to create meetings, the **Calendar API** to discover and auto-join scheduled meetings, and the **Drive API** to access meeting transcripts shared via email. These APIs require a service account with domain-wide delegation, which is only available in Google Workspace.

## Google Workspace Setup

Follow the [Google Workspace Setup Guide](doc/google-workspace-setup.md) to create the dedicated user, service account, and configure domain-wide delegation.

## Quick Start

```bash
# 1. Run the setup wizard
./setup.sh

# 2. Start Stella
docker compose up --build

# 3. Create the web admin user
docker compose exec stella stella web setup
```

The setup wizard generates `stella-data/config/stella.toml` and `docker-compose.yml`. The knowledge base runs on a local PostgreSQL database included automatically.

### Web Management UI

After running `stella web setup`, the web interface is available at:

```
http://localhost:5180
```

From the web UI you can:
- Manage the knowledge base (peers, documents, meetings)
- Create or join meetings on the fly
- Accept or reject calendar invitations
- Configure all settings (Google, Agent, Calendar, Email, Backup)
- Run configuration health checks
- Create and restore database backups
- Manage user accounts

Re-run `./setup.sh` any time to change base settings, or use the web interface for runtime configuration. See the [Usage Guide](doc/usage.md) for the full command reference and detailed examples.

## stella-data Directory

```
stella-data/
├── config/               # stella.toml configuration
├── logs/                 # Stella and Chrome logs
├── credentials/          # Service account JSON
├── chrome-profile/       # Chrome user data (persists login)
├── backup/               # Database backups
├── postgresql/           # PostgreSQL data
├── uploads/              # Uploaded document originals
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
| Calendar not polling | Verify credentials file + google email in Settings |
| Google login fails | Check `stella-data/logs/google-login.log`, verify password + TOTP in Settings |
| RAG not starting | Check database password in stella.toml; re-run `./setup.sh` |
| Web UI not accessible | Ensure port 5180 is mapped in docker-compose.yml |
