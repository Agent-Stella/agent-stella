#!/usr/bin/env bash
set -euo pipefail

# ── Stella Setup Wizard ──────────────────────────────────────────
# Produces a ready-to-run stella.toml and docker-compose.yml.
# Idempotent: re-run any time to change settings.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/stella-data/config"
CONFIG_FILE="$CONFIG_DIR/stella.toml"
TPL_DIR="$CONFIG_DIR/tpl"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# ── Helpers ──────────────────────────────────────────────────────

prompt() {
  local var="$1" label="$2" default="$3" secret="${4:-false}"
  local display_default="$default"
  if [[ "$secret" == "true" && -n "$default" ]]; then
    display_default="********"
  fi

  if [[ -n "$display_default" ]]; then
    label="$label [$display_default]"
  fi

  local value
  if [[ "$secret" == "true" ]]; then
    read -rsp "  $label: " value
    echo
  else
    read -rp "  $label: " value
  fi

  if [[ -z "$value" ]]; then
    value="$default"
  fi
  eval "$var=\"\$value\""
}

# Read a value from existing stella.toml (best-effort).
toml_get() {
  local key="$1"
  if [[ -f "$CONFIG_FILE" ]]; then
    # Match: key = "value" or key = 'value' or key = value
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" "$CONFIG_FILE" | tail -1
  fi
}

current_compose_has_postgres() {
  [[ -f "$COMPOSE_FILE" ]] && grep -q 'pgvector/pgvector' "$COMPOSE_FILE" 2>/dev/null
}

# ── Banner ───────────────────────────────────────────────────────

echo ""
echo "Welcome to Stella Setup!"
echo ""

# ── Load existing defaults ───────────────────────────────────────

cur_openai_key="$(toml_get openai_api_key)"
cur_google_email="$(toml_get google_email)"
cur_google_password="$(toml_get google_password)"
cur_totp_secret="$(toml_get totp_secret)"
cur_app_password="$(toml_get app_password)"
# Extract credentials_file, stripping the container prefix for display.
cur_credentials_file_raw="$(toml_get credentials_file)"
cur_credentials_file="${cur_credentials_file_raw#/app/data/}"
cur_rag_api_key="$(toml_get api_key)"
cur_db_password="$(toml_get password)"

# Detect current RAG mode from existing config.
cur_rag_mode="disabled"
if [[ -n "$cur_rag_api_key" ]] && current_compose_has_postgres; then
  cur_rag_mode="builtin"
elif [[ -n "$cur_rag_api_key" ]]; then
  cur_rag_mode="external"
fi

# ── 1. OpenAI API Key ───────────────────────────────────────────

echo "1. OpenAI is used for realtime voice and managing RAG vectors."
echo "   Provide an OpenAI API key that supports both."
echo ""
prompt openai_key "OpenAI API Key (required)" "$cur_openai_key" true

if [[ -z "$openai_key" ]]; then
  echo "Error: OpenAI API key is required."
  exit 1
fi

# ── 2. Google integration level ─────────────────────────────────

echo ""
echo "2. Stella integrates with Calendar and Email. Do you want full integration?"
echo "   a) Yes, full integration (recommended)"
echo "   b) No, just basic Google Meet access"

# Determine default based on existing config.
google_default="a"
if [[ -z "$cur_credentials_file" && -z "$cur_app_password" ]]; then
  google_default="b"
fi
read -rp "  Choice [$google_default]: " google_choice
google_choice="${google_choice:-$google_default}"

google_email=""
google_password=""
totp_secret=""
app_password=""
credentials_file=""
calendar_enabled="false"
email_enabled="false"

case "$google_choice" in
  a|A)
    echo ""
    prompt google_email "Google email" "$cur_google_email"
    prompt google_password "Google password" "$cur_google_password" true
    prompt totp_secret "TOTP secret (2FA)" "$cur_totp_secret" true
    prompt app_password "App password (IMAP)" "$cur_app_password" true
    prompt credentials_file "Service account file (relative to stella-data/)" "${cur_credentials_file:-credentials/sa.json}"
    calendar_enabled="true"
    email_enabled="true"
    ;;
  b|B)
    # Basic mode: no credentials needed, Chrome handles Meet access.
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

# ── 3. Knowledge base ───────────────────────────────────────────

echo ""
echo "3. Stella can have a Knowledge Base, so called RAG. It can run on a local"
echo "   database (no setup needed, perfect for data sovereignty) or an external"
echo "   one. Do you want to enable RAG?"
echo "   a) Built-in database — no setup needed (recommended)"
echo "   b) External database"
echo "   c) Disabled"

# Default based on current mode.
case "$cur_rag_mode" in
  builtin)  rag_default="a" ;;
  external) rag_default="b" ;;
  *)        rag_default="c" ;;
esac
read -rp "  Choice [$rag_default]: " rag_choice
rag_choice="${rag_choice:-$rag_default}"

rag_api_key=""
db_host=""
db_port=""
db_name=""
db_user=""
db_password=""
db_sslmode=""
use_builtin_db=false

case "$rag_choice" in
  a|A)
    use_builtin_db=true
    rag_api_key="${cur_rag_api_key:-sk-stella-$(openssl rand -hex 24)}"
    db_host="postgres"
    db_port="5432"
    db_name="stella"
    db_user="stella"
    db_password="${cur_db_password:-$(openssl rand -hex 16)}"
    db_sslmode="disable"
    ;;
  b|B)
    rag_api_key="${cur_rag_api_key:-sk-stella-$(openssl rand -hex 24)}"
    echo ""
    prompt db_host "Database host" "${cur_db_host:-localhost}"
    prompt db_port "Database port" "5432"
    prompt db_name "Database name" "stella"
    prompt db_user "Database user" "stella"
    prompt db_password "Database password" "$cur_db_password" true
    prompt db_sslmode "SSL mode (disable/require)" "disable"
    ;;
  c|C)
    # RAG disabled — no config needed.
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

# ── Downgrade check: postgres removal ───────────────────────────

if current_compose_has_postgres && [[ "$use_builtin_db" == "false" ]]; then
  echo ""
  echo "Warning: This will remove the local PostgreSQL database and all stored data."
  read -rp "Proceed? [y/N]: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted — no changes made."
    exit 0
  fi
  echo "Cleaning up containers and volumes..."
  (cd "$SCRIPT_DIR" && docker compose down -v 2>/dev/null || true)
  docker rmi pgvector/pgvector:pg17 2>/dev/null || true
fi

# ── Write stella.toml ────────────────────────────────────────────

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << TOML
# ─────────────────────────────────────────────────────────────
# Stella Configuration — generated by setup.sh
# ─────────────────────────────────────────────────────────────

# ── Core credentials ──────────────────────────────────────────

[basic]
openai_api_key = "$openai_key"
TOML

if [[ -n "$google_email" ]]; then
  cat >> "$CONFIG_FILE" << TOML
google_email = "$google_email"
TOML
fi
if [[ -n "$google_password" ]]; then
  cat >> "$CONFIG_FILE" << TOML
google_password = "$google_password"
TOML
fi
if [[ -n "$totp_secret" ]]; then
  cat >> "$CONFIG_FILE" << TOML
totp_secret = "$totp_secret"
TOML
fi
if [[ -n "$app_password" ]]; then
  cat >> "$CONFIG_FILE" << TOML
app_password = "$app_password"
TOML
fi

cat >> "$CONFIG_FILE" << TOML

# ── Agent identity & behavior ─────────────────────────────────

[agent]
name = "Stella"
default_voice = "coral"
default_lang = "English"
listen_only = false
enable_notes = true
auto_accept_guests = true

# ── Logging ───────────────────────────────────────────────────

[logs]
dir = "stella-data/logs"
rotate_time = "00:00"
retention_days = 30

# ── Chrome / CDP ──────────────────────────────────────────────

[chrome]
debug_addr = "http://127.0.0.1:18800"

# ── Calendar integration ──────────────────────────────────────

[calendar]
enabled = $calendar_enabled
TOML

if [[ -n "$credentials_file" ]]; then
  # Write the container-absolute path (/app/data/ maps to stella-data/ on host).
  credentials_container_path="/app/data/$credentials_file"
  cat >> "$CONFIG_FILE" << TOML
credentials_file = "$credentials_container_path"
TOML
fi

cat >> "$CONFIG_FILE" << TOML
calendar_id = "primary"
scan_interval = 5

# ── Email scanning ────────────────────────────────────────────

[email]
enabled = $email_enabled
scan_interval = 10
keywords = ["notes", "transcript", "meeting", "summary", "recording"]

# ── Owner notifications ───────────────────────────────────────

[owner]
# name = "Your Name"
# email = "you@example.com"
TOML

# RAG section.
if [[ -n "$rag_api_key" ]]; then
  cat >> "$CONFIG_FILE" << TOML

# ── RAG (knowledge base) ─────────────────────────────────────

[rag]
api_key = "$rag_api_key"

[rag.database]
host = "$db_host"
port = $db_port
name = "$db_name"
user = "$db_user"
password = "$db_password"
sslmode = "$db_sslmode"
TOML
fi

# ── Write docker-compose.yml ────────────────────────────────────

if [[ "$use_builtin_db" == "true" ]]; then
  sed "s/__DB_PASSWORD__/$db_password/g" "$TPL_DIR/docker-compose.rag.yml" > "$COMPOSE_FILE"
else
  cp "$TPL_DIR/docker-compose.yml" "$COMPOSE_FILE"
fi

# ── Done ─────────────────────────────────────────────────────────

echo ""
echo "All set! Configuration written to stella-data/config/stella.toml"
echo ""
echo "Start Stella:"
echo "  docker compose up --build"
echo ""
