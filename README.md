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

### 1. Create a dedicated Workspace user

In **Google Workspace Admin** (`admin.google.com`) → Directory → Users, create a user for the agent (e.g., `stella@yourdomain.com`).

### 2. Configure the user account

Sign in as the new user and complete these steps:

1. Enable **2-Step Verification** at https://myaccount.google.com/signinoptions/two-step-verification — choose the **Authenticator app** option and save the TOTP secret (the text code shown during setup). Stella uses it for automated Chrome login.
2. Generate an **App Password** at https://myaccount.google.com/apppasswords — Stella uses it for IMAP access to scan transcription emails.

### 3. Create a GCP project and enable APIs

In **Google Cloud Console** (`console.cloud.google.com`):

1. Create a new project (or use an existing one).
2. Go to **APIs & Services → Library** and enable:
   - Google Calendar API
   - Google Meet REST API
   - Google Drive API

### 4. Create a service account

Still in **Google Cloud Console**:

1. Go to **IAM & Admin → Service Accounts** and create a new service account.
2. On the service account details page, go to the **Keys** tab → **Add Key → Create new key** → JSON. Save the downloaded file to `stella-data/credentials/`.

### 5. Set up domain-wide delegation

This step connects the GCP service account to your Workspace domain so it can act on behalf of the agent user.

1. In **Google Cloud Console**, go to the service account details page and note the **Client ID** (a numeric ID, not the email).
2. In **Google Workspace Admin** (`admin.google.com`), go to **Security → Access and data control → API controls → Domain-wide delegation → Manage Domain Wide Delegation**.
3. Click **Add new** and enter:
   - **Client ID**: the numeric ID from step 1
   - **OAuth scopes** (comma-separated):
     ```
     https://www.googleapis.com/auth/calendar.events,https://www.googleapis.com/auth/meetings.space.created,https://www.googleapis.com/auth/drive.readonly
     ```
4. Click **Authorize**.

## Quick Start

```bash
# 1. Run the setup wizard
./setup.sh

# 2. Start Stella
docker compose up --build
```

The wizard walks you through two steps: OpenAI API key and Google Workspace credentials. It generates `stella-data/config/stella.toml` and `docker-compose.yml` — ready to go. The knowledge base (RAG) is always included with a local PostgreSQL database.

Re-run `./setup.sh` any time to change settings. Your previous inputs are preserved as defaults, so you only need to override what you want to change. You can also edit `stella-data/config/stella.toml` directly (see `stella.toml.example` for the full reference).

## What Stella Can Do

### Meetings

Create a meeting on the spot or join an existing one:

```bash
# Create a new meeting and join it
docker compose exec stella stella meet create --context "Weekly sync"

# Join an existing meeting
docker compose exec stella stella meet join https://meet.google.com/abc-defg-hij

# With specific voice, language, and context
docker compose exec stella stella meet join \
  --voice ash --lang español \
  --context "Q1 review — focus on revenue targets" \
  https://meet.google.com/abc-defg-hij
```

### Calendar Integration

Stella monitors her Google Calendar and autonomously joins meetings:

- **Auto-discovery**: Scans the calendar every 5 minutes for upcoming events with a Google Meet link.
- **Auto-accept**: If the event host is a known peer in Stella's memory (RAG), the invitation is accepted automatically.
- **Owner notification**: If the host is unknown, Stella notifies the owner so they can accept or reject the invitation.
- **Auto-join**: Joins the meeting 10 minutes before the scheduled start time, with a briefing prepared from the RAG.

### Hosting Meetings

When Stella is the meeting organizer (e.g., a meeting created by Stella herself or orchestrated through an external agent like Openclaw):

- **Guest admission**: Automatically admits participants from the lobby.
- **Gemini transcription**: Enables Google's built-in Gemini notes and transcription.

### Email & Transcript Ingestion

Stella scans her inbox for meeting transcriptions from services like Otter.ai, Fireflies, Google Meet recordings, and others. These are automatically ingested into the knowledge base, building Stella's institutional memory over time.

### Knowledge Base (RAG)

Stella maintains a knowledge base backed by a local PostgreSQL/pgvector database. It stores documents, peer profiles, and meeting history — all searchable via hybrid search (semantic + full-text) during meetings. RAG is always active and included automatically.

#### Manual document management

```bash
# Ingest a document
docker compose exec stella stella rag document ingest \
  --title "Company Handbook" --type pdf --source /app/data/docs/handbook.pdf

# Search the knowledge base
docker compose exec stella stella rag search "quarterly revenue targets"

# List all documents
docker compose exec stella stella rag document list

# Manage peer profiles
docker compose exec stella stella rag peer create \
  --name "Jane Smith" --email jane@example.com --position "VP Engineering"
docker compose exec stella stella rag peer list
```

#### Integration with external agents

The RAG server exposes a REST API and MCP (Model Context Protocol) interface on port 8080 inside the container. This allows external agents like **Openclaw** to ingest documents from various channels (Slack, Telegram, email, web) directly into Stella's knowledge base, keeping her always up to date.

## All Commands

```bash
# While the daemon is running:
docker compose exec stella stella <command>

# Without the daemon (fast, no Chrome startup):
docker compose run stella stella <command>
```

| Command | Description |
|---------|-------------|
| `stella meet join [flags] <url>` | Join an existing Google Meet call |
| `stella meet create [flags]` | Create a new meeting and join it |
| `stella rag search <query>` | Search the knowledge base |
| `stella rag document list\|ingest\|update\|delete` | Manage documents |
| `stella rag peer list\|show\|create\|update\|delete` | Manage peer profiles |
| `stella rag meeting list\|show\|create\|update\|delete` | Manage meeting records |
| `stella rag migrate` | Run database migrations |
| `stella backup dump\|restore\|list` | Database backup and restore |
| `stella validate` | Check configuration and print status |
| `stella version` | Print version |
| `stella screenshot` | Debug: screenshot current Chrome tab |

See the [Usage Guide](doc/usage.md) for detailed syntax, examples, and all available options for every command.

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
| RAG not starting | Check `rag.database.password` in stella.toml; re-run `./setup.sh` |
