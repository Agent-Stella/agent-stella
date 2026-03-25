# Stella Usage Guide

Complete reference for all Stella commands, flags, and options.

## Running Commands

Stella runs inside Docker. There are two ways to execute commands:

```bash
# While the daemon is running — connects to the existing container:
docker compose exec stella stella <command>

# Without the daemon — starts a temporary container (no Chrome, fast):
docker compose run stella stella <command>
```

Use `exec` when you need Chrome (joining meetings, screenshots). Use `run` for everything else (RAG operations, backup, validate).

General command format:

```
stella <command> [subcommand] [flags] [arguments]
```

---

## The Daemon

```bash
docker compose up
```

The daemon **is** Stella's scheduler. It runs a 1-minute heartbeat loop and manages all recurring and one-shot jobs:

| Job | Interval | Description |
|-----|----------|-------------|
| Calendar scan | 5 min (configurable) | Discovers upcoming meetings and schedules joins |
| Email scan | 10 min (configurable) | Scans inbox for meeting transcripts to ingest |
| Log rotation | 1 hour | Prunes old log files (default: 30 days retention) |
| Notification cache GC | 24 hours | Cleans up dedup cache for owner notifications |
| Database backup | daily/weekly/monthly | Creates PostgreSQL backups (if enabled) |

**One-shot jobs**: When the calendar scan finds an upcoming meeting, it schedules a one-shot join 10 minutes before the meeting start time.

**Single instance**: The daemon uses a PID file (`stella-data/pids/daemon.pid`) to ensure only one instance runs at a time.

**Embedded RAG server**: The daemon automatically starts the RAG HTTP server on port 8080 and runs database migrations on startup. You don't need to start it separately.

**Graceful shutdown**: Handles SIGINT/SIGTERM. You can also create `/tmp/stella-stop` inside the container to trigger a shutdown.

---

## Meetings

### Joining a Meeting

```
stella meet join [flags] <meet-url>
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--voice` | string | `coral` | Voice for the agent (see voices below) |
| `--lang` | string | `English` | Language the agent should respond in |
| `--context` | string | | Additional context injected into the system prompt |
| `--instructions` | string | | Style instructions for agent responses |
| `--participants` | string | | Comma-separated list of participants with roles |
| `--enable-notes` | bool | `true` | Activate Gemini notes/transcription on entry |
| `--auto-accept-guests` | bool | `false` | Admit waiting guests every 10 seconds |

**Available voices**: `alloy`, `ash`, `ballad`, `coral` (default), `echo`, `sage`, `shimmer`, `verse`

**Examples:**

```bash
# Basic join
stella meet join https://meet.google.com/abc-defg-hij

# With voice and language
stella meet join --voice sage --lang español https://meet.google.com/abc-defg-hij

# With meeting context and participant info
stella meet join \
  --context "Q1 review — focus on revenue targets" \
  --participants "Alice (PM), Bob (Engineering Lead)" \
  https://meet.google.com/abc-defg-hij

# With style instructions
stella meet join \
  --instructions "Keep answers brief and use bullet points" \
  https://meet.google.com/abc-defg-hij
```

**Notes:**
- `--enable-notes` and `--auto-accept-guests` only work when Stella is the meeting organizer/host.
- `--participants` is optional — when joining via calendar, participants are loaded from the briefing automatically.
- `--context` is useful for giving Stella focus: "Weekly ops review — focus on driver KPIs", "Client demo — highlight new features", etc.

### Creating a Meeting

```
stella meet create [flags]
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--title` | string | `Stella Meeting` | Event title |
| `--duration` | int | `30` | Duration in minutes |
| `--start` | string | `now` | Start time (RFC3339 or `2006-01-02T15:04`) |
| `--no-join` | bool | `false` | Only create the event, don't join |
| `--open` | bool | `false` | Anyone can join without knocking |
| `--voice` | string | from config | Voice for the agent |
| `--lang` | string | from config | Language for the agent |

**Examples:**

```bash
# Quick meeting, join immediately
stella meet create --title "Team Standup" --duration 15

# Schedule for later, don't join yet
stella meet create --title "Client Call" --start "2026-03-21T14:00" --no-join

# Open meeting (no lobby)
stella meet create --title "Office Hours" --open --duration 60
```

**Access modes:**
- Default: **Trusted** — organization members join freely, external users must knock.
- `--open`: **Open** — anyone with the link joins without knocking.

**When Stella is the organizer** (i.e., meetings she creates):
- Guest admission is automatic (admits participants from the lobby every 10 seconds).
- Gemini notes and transcription are activated on entry.

### Calendar Integration (Automatic Joining)

When the daemon is running, Stella monitors her Google Calendar automatically:

1. **Scan**: Every 5 minutes, scans the next 60 minutes for events with a Google Meet link.
2. **Auto-accept**: If the event organizer is a known peer (added via `stella rag peer`), the invitation is accepted automatically.
3. **Owner notification**: If the organizer is unknown, Stella emails the owner so they can accept or reject.
4. **Schedule join**: Accepted meetings are scheduled as one-shot jobs, joining 10 minutes before start.
5. **Briefing preparation**: Before joining, Stella prepares a briefing — looks up peer profiles, retrieves previous meeting transcripts, and builds context from the knowledge base.

**Manual calendar commands:**

```bash
# Check for pending events (one-shot, same as what the daemon does)
stella calendar check

# Accept or reject a specific event
stella calendar accept <event-id>
stella calendar reject <event-id>
```

### Listen-Only Mode

When `listen_only = true` in config (or `STELLA_LISTEN_ONLY=true`), Stella stays silent unless someone explicitly addresses her by name. Useful for passive observation — she still listens and can answer when called on.

---

## Knowledge Base (RAG)

### What the RAG Does

The RAG is Stella's persistent memory. Every document you ingest — company handbooks, product specs, meeting transcripts — becomes available to Stella in her next meeting. When someone asks a question, Stella searches her knowledge base using hybrid search (semantic similarity + keyword matching via Reciprocal Rank Fusion) and uses the results to inform her answer.

**This means Stella remembers everything across meetings.** When a transcript from Monday's standup is ingested, Stella can reference it in Tuesday's planning meeting. Combined with email scanning (which auto-ingests transcripts from Otter.ai, Fireflies, Google Meet, etc.), Stella builds institutional memory over time without manual effort.

### Documents

```
stella rag document <action> [flags]
```

#### List all documents

```bash
stella rag document list
```

#### Ingest a document

```
stella rag document ingest --title <title> --type <type> (--source <value> | --file <path>) [flags]
```

| Flag | Type | Required | Description |
|------|------|----------|-------------|
| `--title` | string | yes | Document title |
| `--type` | string | yes | Source type (see table below) |
| `--source` | string | conditional | URL (for `web`) or text content (for `text`) |
| `--file` | string | conditional | File path (for `pdf`, `docx`, `pptx`) |
| `--metadata` | JSON | no | JSON metadata object |
| `--meeting-id` | string | no | Associate document with a meeting record |

Either `--source` or `--file` is required, depending on the type.

**Document types:**

| Type | Source | Description |
|------|--------|-------------|
| `pdf` | `--file` | PDF document — parsed with pymupdf |
| `docx` | `--file` | Microsoft Word document |
| `pptx` | `--file` | Microsoft PowerPoint presentation |
| `web` | `--source` (URL) | Web page — fetched and extracted with trafilatura |
| `text` | `--source` (text) | Plain text content — passed directly |

**Examples:**

```bash
# Ingest a PDF
stella rag document ingest \
  --title "Company Handbook" --type pdf --file /app/data/docs/handbook.pdf

# Ingest a web page
stella rag document ingest \
  --title "Product Blog Post" --type web --source "https://example.com/blog/post"

# Ingest plain text
stella rag document ingest \
  --title "Meeting Notes" --type text --source "Discussed roadmap priorities..."

# Ingest a Word document with metadata
stella rag document ingest \
  --title "Q4 Report" --type docx --file /app/data/docs/report.docx \
  --metadata '{"author": "Jane", "quarter": "Q4"}'

# Ingest a PowerPoint
stella rag document ingest \
  --title "Sales Deck" --type pptx --file /app/data/docs/sales.pptx

# Associate with a meeting
stella rag document ingest \
  --title "Standup Transcript" --type text --source "..." \
  --meeting-id "uuid-of-meeting"
```

**File paths in Docker**: Files must be accessible inside the container. Place them in `stella-data/` (mounted at `/app/data/`) or mount additional volumes.

#### Update a document

```bash
stella rag document update <id> --notes "Additional context about this document"
```

#### Delete a document

```bash
stella rag document delete <id>
```

### Search

```
stella rag search <query> [flags]
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--limit` | int | `10` | Maximum number of results |
| `--semantic-weight` | float | from config | Weight for semantic (vector) search (0.0–1.0) |
| `--fulltext-weight` | float | from config | Weight for full-text (keyword) search (0.0–1.0) |

Stella uses **hybrid search**: semantic search finds conceptually similar content, full-text search finds exact keyword matches. Results are combined using Reciprocal Rank Fusion (RRF). Adjust the weights to favor one method over the other.

**Examples:**

```bash
# Default hybrid search
stella rag search "quarterly revenue targets"

# Favor semantic similarity
stella rag search "how do we handle customer complaints" \
  --semantic-weight 0.8 --fulltext-weight 0.2

# Keyword-heavy search
stella rag search "API rate limit 429" \
  --semantic-weight 0.2 --fulltext-weight 0.8 --limit 5
```

### Peers

```
stella rag peer <action> [flags]
```

Peers represent people Stella interacts with. They serve two purposes:
1. **Calendar auto-accept**: Meetings organized by known peers are accepted automatically.
2. **Meeting briefings**: Peer profiles are included in Stella's briefing before a meeting, so she knows who she's talking to.

#### List all peers

```bash
stella rag peer list
```

#### Show a peer

```bash
stella rag peer show <id>
```

#### Create a peer

```
stella rag peer create --name <name> [flags]
```

| Flag | Type | Required | Description |
|------|------|----------|-------------|
| `--name` | string | yes | Full name |
| `--email` | string | no | Email address (used for calendar auto-accept matching) |
| `--company` | string | no | Company name |
| `--position` | string | no | Job position/title |
| `--department` | string | no | Department |
| `--language` | string | no | Preferred language |
| `--notes` | string | no | Notes about this person (visible to the agent) |
| `--metadata` | JSON | no | JSON metadata object |

**Examples:**

```bash
# Basic peer
stella rag peer create --name "Jane Smith" --email jane@example.com

# Full profile
stella rag peer create \
  --name "Eduardo Martins" \
  --email eduardo@company.com \
  --company "Acme Corp" \
  --position "COO" \
  --department "Operations" \
  --language "Portuguese" \
  --notes "Prefers concise updates, focus on KPIs"
```

#### Update a peer

```bash
stella rag peer update <id> --position "CTO" --notes "Promoted in Q1"
```

Same flags as `create`; all optional.

#### Delete a peer

```bash
stella rag peer delete <id>
```

### Meetings

```
stella rag meeting <action> [flags]
```

Meeting records track Stella's meeting history and link to documents/transcripts.

#### List all meetings

```bash
stella rag meeting list
```

#### Show a meeting

```bash
stella rag meeting show <id>
```

#### Create a meeting

```
stella rag meeting create --attendees <names> [flags]
```

| Flag | Type | Required | Description |
|------|------|----------|-------------|
| `--attendees` | string | yes | Comma-separated attendee names |
| `--title` | string | no | Meeting title |
| `--attendee-ids` | string | no | Comma-separated attendee UUIDs |
| `--planned-at` | string | no | Planned time (ISO 8601) |
| `--started-at` | string | no | Start time (ISO 8601) |
| `--url` | string | no | Meeting URL |
| `--voice` | string | no | Voice used for this meeting |
| `--language` | string | no | Meeting language |
| `--context` | string | no | Meeting context |
| `--instructions` | string | no | Agent instructions |
| `--metadata` | JSON | no | JSON metadata object |

**Example:**

```bash
stella rag meeting create \
  --attendees "Alice Smith, Bob Jones" \
  --title "Q4 Planning" \
  --planned-at "2026-03-25T14:00:00Z" \
  --language "English"
```

#### Update a meeting

```bash
stella rag meeting update <id> --title "Q4 Planning (Revised)"
```

Same flags as `create`; all optional.

#### Delete a meeting

```bash
stella rag meeting delete <id>
```

### Migrations

```bash
stella rag migrate
```

Runs database migrations against the configured PostgreSQL database. The daemon runs this automatically on startup, but you can run it manually after an upgrade.

### RAG Server

```bash
stella rag serve [port]
```

Starts the RAG HTTP/MCP server standalone on the specified port (default: 8080). The daemon starts this automatically — use this only if you need to run the RAG server without the daemon.

---

## Email Integration

```bash
stella email check
```

Performs a one-shot scan for meeting-related emails. This is the same scan the daemon runs automatically every 10 minutes.

**How it works:**
1. Connects to Gmail via the Gmail API using OAuth 2.0.
2. Searches for unread emails with subject keywords: `notes`, `transcript`, `meeting`, `summary`, `recording`.
3. Extracts Google Docs links from matching emails.
4. Fetches document content via the Google Drive API.
5. Ingests the content into the RAG knowledge base.
6. Deduplicates — the same document is never ingested twice.
7. When the same document later appears in a calendar event, it is linked to the meeting automatically.

**This is how Stella builds memory automatically.** When a meeting notetaker (Gemini, Otter.ai, Fireflies) emails notes to Stella's Google account, they're ingested immediately. After the meeting ends, Stella also polls the calendar event for up to 1 hour to find linked notes/transcripts and associate them with the correct meeting record.

**Configuration** (in `stella.toml`):

```toml
[email]
scan_interval = 10                   # Minutes between scans
keywords = ["notes", "transcript", "meeting", "summary", "recording"]
senders = []                         # Optional: filter by sender email
```

**Requirements:**
- Google OAuth must be connected (Settings > Google > Connect Google Account)

---

## Tools

### Backup

```
stella backup <action>
```

| Action | Description |
|--------|-------------|
| `dump` | Create a database backup using `pg_dump` (custom format) |
| `restore <file>` | Restore from a backup file using `pg_restore` |
| `list` | List available backups |

**Examples:**

```bash
stella backup dump
stella backup list
stella backup restore stella-backup-2026-03-21T093000.dump
```

Backups are stored in `stella-data/backup/`.

**Automatic backups** (when daemon is running):

```toml
[rag.backup]
mode = "daily"          # off, daily, weekly, monthly
time = "03:00"          # Time of day (HH:MM)
retention = 7           # Number of backups to keep
dir = "stella-data/backup"
```

### Validate

```bash
stella validate
```

Checks configuration and prints the status of every component: agent settings, Chrome, OpenAI API key, Google credentials, calendar, email, RAG database, owner notifications, and log directory. Reports any errors found.

Exit code `0` = valid, `1` = errors found.

### Version

```bash
stella version
```

Prints the current version.

### Screenshot

```bash
stella screenshot
```

Captures a PNG screenshot of the current Chrome tab and saves it with a timestamp (e.g., `screenshot_20260321_093000.png`). Useful for debugging — see what Chrome sees.

To copy the screenshot out of Docker:

```bash
docker compose cp stella:/app/screenshot_20260321_093000.png .
```

### Upgrade

```
stella upgrade <action>
```

| Action | Description |
|--------|-------------|
| `check` | Check GitHub for a newer version |
| `apply` | Download and replace the current binary |

```bash
stella upgrade check
stella upgrade apply
```

Restart the daemon after applying an upgrade.

---

## Configuration Reference

Stella is configured via `stella-data/config/stella.toml`. All settings can also be set via environment variables (useful in Docker).

### Agent Settings

```toml
[agent]
name = "Stella"              # Display name in meetings
default_voice = "coral"      # alloy, ash, ballad, coral, echo, sage, shimmer, verse
default_lang = "English"     # Default response language
listen_only = false          # Only respond when addressed by name
enable_notes = true          # Activate Gemini notes in meetings
auto_accept_guests = true    # Auto-admit guests from lobby
```

| Env Variable | Setting |
|---|---|
| `STELLA_AGENT_NAME` | `agent.name` |
| `STELLA_DEFAULT_VOICE` | `agent.default_voice` |
| `STELLA_DEFAULT_LANG` | `agent.default_lang` |
| `STELLA_LISTEN_ONLY` | `agent.listen_only` |
| `STELLA_ENABLE_NOTES` | `agent.enable_notes` |
| `STELLA_AUTO_ACCEPT_GUESTS` | `agent.auto_accept_guests` |

### Credentials

```toml
[basic]
openai_api_key = ""
google_email = ""
google_password = ""
totp_secret = ""
oauth_client_id = ""
oauth_client_secret = ""
```

| Env Variable | Setting |
|---|---|
| `OPENAI_API_KEY` | `basic.openai_api_key` |
| `GOOGLE_EMAIL` | `basic.google_email` |
| `GOOGLE_PASSWORD` | `basic.google_password` |
| `GOOGLE_TOTP_SECRET` | `basic.totp_secret` |
| `GOOGLE_OAUTH_CLIENT_ID` | `basic.oauth_client_id` |
| `GOOGLE_OAUTH_CLIENT_SECRET` | `basic.oauth_client_secret` |

### Calendar

```toml
[calendar]
calendar_id = "primary"
scan_interval = 5            # Minutes between scans
```

| Env Variable | Setting |
|---|---|
| `GOOGLE_CALENDAR_ID` | `calendar.calendar_id` |
| `STELLA_CALENDAR_INTERVAL` | `calendar.scan_interval` |

Calendar is auto-enabled when OAuth is connected and `google_email` is configured.

### Email

```toml
[email]
scan_interval = 10
keywords = ["notes", "transcript", "meeting", "summary", "recording"]
senders = []
```

| Env Variable | Setting |
|---|---|
| `STELLA_EMAIL_INTERVAL` | `email.scan_interval` |
| `STELLA_EMAIL_KEYWORDS` | `email.keywords` (comma-separated) |
| `STELLA_EMAIL_SENDERS` | `email.senders` (comma-separated) |

Email is auto-enabled when OAuth is connected and `google_email` is configured.

### RAG & Database

```toml
[rag]
url = "http://localhost:8080"
api_key = ""

[rag.database]
host = "localhost"
port = 5432
name = "stella"
user = "stella"
password = ""

[rag.backup]
mode = "off"                 # off, daily, weekly, monthly
time = "03:00"
retention = 7
dir = "stella-data/backup"

[rag.embedding]
model = "text-embedding-3-small"
dimensions = 1536
batch_size = 100

[rag.chunking]
chunk_size = 512
overlap = 50

[rag.search]
match_count = 10
semantic_weight = 1.0
full_text_weight = 1.0
```

| Env Variable | Setting |
|---|---|
| `STELLA_RAG_URL` | `rag.url` |
| `STELLA_RAG_KEY` | `rag.api_key` |
| `STELLA_DB_HOST` | `rag.database.host` |
| `STELLA_DB_PORT` | `rag.database.port` |
| `STELLA_DB_NAME` | `rag.database.name` |
| `STELLA_DB_USER` | `rag.database.user` |
| `STELLA_DB_PASSWORD` | `rag.database.password` |

### Chrome

```toml
[chrome]
debug_addr = "http://127.0.0.1:18800"
```

| Env Variable | Setting |
|---|---|
| `CHROME_DEBUG_ADDR` | `chrome.debug_addr` |

### Owner Notifications

```toml
[owner]
name = ""
email = ""
```

| Env Variable | Setting |
|---|---|
| `AGENT_OWNER_NAME` | `owner.name` |
| `AGENT_OWNER_EMAIL` | `owner.email` |

### Logs

```toml
[logs]
dir = ""                     # Default: stella-data/logs
rotate_time = "00:00"
retention_days = 30
```

| Env Variable | Setting |
|---|---|
| `STELLA_LOG_DIR` | `logs.dir` |
