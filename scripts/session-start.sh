#!/bin/bash
# Called by SessionStart hook — records session start time and initializes state
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
mkdir -p "$STATE_DIR"

SESSION_FILE="$STATE_DIR/current-session.json"
HISTORY_FILE="$STATE_DIR/session-history.jsonl"

# Read session_id from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Initialize session state (using jq for safe JSON construction)
NOW=$(date +%s)
jq -n --arg sid "$SESSION_ID" --argjson ts "$NOW" '{
  session_id: $sid,
  start_ts: $ts,
  prompt_count: 0,
  breaks_taken: 0,
  last_break_ts: $ts,
  intention: null
}' > "$SESSION_FILE"
