# agent-stella — Command Reference

All commands can be run directly or inside the Docker container:

```bash
# Direct
agent-stella <command>

# Inside Docker
docker compose exec stella agent-stella <command>
```

---

## daemon

Run the background daemon with calendar integration and email scanning.

```bash
agent-stella daemon
```

The daemon starts a 1-minute heartbeat loop and registers periodic jobs:
- **Calendar scan** every 5 minutes (configurable via `STELLA_CALENDAR_INTERVAL`)
- **Email scan** every 10 minutes (configurable via `STELLA_EMAIL_INTERVAL`)

When a meeting is found on the calendar, the daemon prepares a briefing via the RAG, joins the meeting, and participates via voice.

---

## meeting join

Join an existing Google Meet call.

```bash
agent-stella meeting join [flags] <meet-url>
```

**Flags:**

| Flag | Default | Description |
|---|---|---|
| `--voice <name>` | `coral` | OpenAI Realtime voice (alloy, ash, ballad, coral, echo, sage, shimmer, verse) |
| `--lang <language>` | `español` | Language the agent should respond in |
| `--context <text>` | — | Additional context for the system prompt |
| `--instructions <text>` | — | Style instructions for responses |
| `--participants <list>` | — | Comma-separated participants with roles |
| `--enable-notes` | `true` | Activate Gemini notes/transcription (host only) |
| `--auto-accept-guests` | `false` | Auto-admit waiting guests every 10s (host only) |

**Examples:**

```bash
# Join with default settings
agent-stella meeting join https://meet.google.com/abc-defg-hij

# Join with guest admission and a specific voice
agent-stella meeting join --voice ash --auto-accept-guests \
  https://meet.google.com/abc-defg-hij

# Join with context and custom instructions
agent-stella meeting join \
  --context "Weekly ops review — focus on driver KPIs" \
  --instructions "Keep answers brief and use bullet points" \
  https://meet.google.com/abc-defg-hij

# Join with known participants
agent-stella meeting join \
  --participants "Iván Belmonte (CTO), Eduardo Martins (COO)" \
  https://meet.google.com/abc-defg-hij
```

---

## meeting create

Create a new Google Meet via Google Calendar and optionally join it.

```bash
agent-stella meeting create [flags]
```

**Flags:**

| Flag | Default | Description |
|---|---|---|
| `--title <text>` | `Stella Meeting` | Calendar event title |
| `--duration <minutes>` | `30` | Meeting duration in minutes |
| `--start <time>` | now | Start time (RFC3339 or `2006-01-02T15:04`) |
| `--no-join` | — | Only create the event, don't join |
| `--open` | — | OPEN access (anyone with link can join). Default is TRUSTED (org members join freely, external users knock) |
| `--voice <name>` | env/`coral` | OpenAI Realtime voice |
| `--lang <language>` | env/`español` | Response language |

By default, the agent creates the meeting and immediately joins it with `--enable-notes` and `--auto-accept-guests` enabled.

**Examples:**

```bash
# Create and join a meeting now
agent-stella meeting create --title "Quick sync"

# Create a meeting for later without joining
agent-stella meeting create \
  --title "Team standup" \
  --start 2026-03-15T09:00 \
  --duration 15 \
  --no-join

# Create an open meeting anyone can join
agent-stella meeting create --title "Office hours" --open --duration 60
```

---

## calendar check

Scan the calendar for upcoming events that need a response.

```bash
agent-stella calendar check
```

Shows events in the next 60 minutes where the agent hasn't accepted or declined yet.

**Requires:** `GOOGLE_CREDENTIALS_FILE`, `GOOGLE_EMAIL`

---

## calendar accept

Accept a calendar event invitation.

```bash
agent-stella calendar accept <event-id>
```

If `AGENT_OWNER_EMAIL` is set, sends a confirmation email to the owner.

**Example:**

```bash
agent-stella calendar accept abc123def456
```

---

## calendar reject

Decline a calendar event invitation.

```bash
agent-stella calendar reject <event-id>
```

If `AGENT_OWNER_EMAIL` is set, sends a confirmation email to the owner.

**Example:**

```bash
agent-stella calendar reject abc123def456
```

---

## email check

Scan for meeting-related emails (transcripts, notes, recordings) and ingest them into the knowledge base.

```bash
agent-stella email check
```

Searches the inbox for emails matching the configured keywords (`STELLA_EMAIL_KEYWORDS`). Extracts content from Google Docs links found in matching emails and ingests them via the RAG.

**Requires:** `GOOGLE_EMAIL`, `GOOGLE_APP_PASSWORD`

**Default keywords:** `notes`, `transcript`, `meeting`, `summary`, `recording`

---

## rag search

Search the RAG knowledge base.

```bash
agent-stella rag search [flags] <query>
```

**Flags:**

| Flag | Default | Description |
|---|---|---|
| `--limit <N>` | `10` | Maximum number of results |
| `--semantic-weight <F>` | auto | Semantic search weight (0.0–1.0) |
| `--fulltext-weight <F>` | auto | Full-text search weight (0.0–1.0) |

**Examples:**

```bash
agent-stella rag search "quarterly revenue report"
agent-stella rag search --limit 5 "onboarding process"
```

---

## rag document

Manage documents in the knowledge base.

### document list

```bash
agent-stella rag document list
```

### document ingest

```bash
agent-stella rag document ingest --title <title> --type <type> [flags]
```

| Flag | Required | Description |
|---|---|---|
| `--title <text>` | Yes | Document title |
| `--type <type>` | Yes | Source type: `pdf`, `web`, `text`, `docx`, `pptx` |
| `--source <text>` | * | Source text or URL |
| `--file <path>` | * | File path to upload |
| `--metadata <json>` | No | JSON metadata |
| `--meeting-id <id>` | No | Associated meeting ID |

\* Either `--source` or `--file` is required.

**Examples:**

```bash
# Ingest a web page
agent-stella rag document ingest \
  --title "Company handbook" \
  --type web \
  --source "https://example.com/handbook"

# Ingest a PDF file
agent-stella rag document ingest \
  --title "Q1 Report" \
  --type pdf \
  --file /path/to/report.pdf
```

### document update

```bash
agent-stella rag document update <id> --notes <text>
```

### document delete

```bash
agent-stella rag document delete <id>
```

---

## rag peer

Manage peer profiles (known contacts).

### peer list

```bash
agent-stella rag peer list
```

### peer show

```bash
agent-stella rag peer show <id>
```

### peer create

```bash
agent-stella rag peer create --name <name> [flags]
```

| Flag | Required | Description |
|---|---|---|
| `--name <text>` | Yes | Full name |
| `--email <text>` | No | Email address |
| `--company <text>` | No | Company name |
| `--position <text>` | No | Job position |
| `--department <text>` | No | Department |
| `--language <text>` | No | Preferred language |
| `--notes <text>` | No | Agent notes |
| `--metadata <json>` | No | JSON metadata |

**Example:**

```bash
agent-stella rag peer create \
  --name "John Doe" \
  --email john@example.com \
  --company "Acme Inc" \
  --position "Engineering Manager"
```

### peer update

```bash
agent-stella rag peer update <id> [flags]
```

Same flags as `peer create` (all optional).

### peer delete

```bash
agent-stella rag peer delete <id>
```

---

## rag meeting

Manage meeting records in the knowledge base.

### meeting list

```bash
agent-stella rag meeting list
```

### meeting show

```bash
agent-stella rag meeting show <id>
```

### meeting create

```bash
agent-stella rag meeting create --attendees <names> [flags]
```

| Flag | Required | Description |
|---|---|---|
| `--attendees <names>` | Yes | Comma-separated attendee names |
| `--title <text>` | No | Meeting title |
| `--attendee-ids <ids>` | No | Comma-separated attendee UUIDs |
| `--planned-at <time>` | No | Planned time (ISO 8601) |
| `--started-at <time>` | No | Started time (ISO 8601) |
| `--url <url>` | No | Meeting URL |
| `--voice <name>` | No | Voice for the agent |
| `--language <lang>` | No | Meeting language |
| `--context <text>` | No | Meeting context |
| `--instructions <text>` | No | Agent instructions |
| `--metadata <json>` | No | JSON metadata |

**Example:**

```bash
agent-stella rag meeting create \
  --attendees "Iván Belmonte, Eduardo Martins" \
  --title "Weekly sync" \
  --planned-at "2026-03-15T10:00:00Z"
```

### meeting update

```bash
agent-stella rag meeting update <id> [flags]
```

Same flags as `meeting create` (all optional).

### meeting delete

```bash
agent-stella rag meeting delete <id>
```

---

## screenshot

Capture a PNG screenshot of what the agent sees in Chrome.

```bash
agent-stella screenshot
```

Prints the filename to stdout. Inside Docker:

```bash
docker compose exec stella agent-stella screenshot
# Copy to host:
docker compose cp stella:/app/screenshot_20260315_120000.png .
```
