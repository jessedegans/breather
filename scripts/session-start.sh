#!/bin/bash
# Called by SessionStart hook -- records session start time and initializes state
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
mkdir -p "$STATE_DIR"

SESSION_FILE="$STATE_DIR/current-session.json"
HISTORY_FILE="$STATE_DIR/session-history.jsonl"

# Read session_id from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Check yesterday's patterns for context
MARATHON_WARNING=""
if [ -f "$HISTORY_FILE" ]; then
  # Count sessions over 90 min in the last 24 hours
  YESTERDAY=$(date -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s 2>/dev/null || echo 0)
  LONG_SESSIONS=$(jq -s "[.[] | select(.end_ts > $YESTERDAY and .duration_min > 90)] | length" "$HISTORY_FILE" 2>/dev/null || echo 0)
  if [ "$LONG_SESSIONS" -ge 2 ]; then
    MARATHON_WARNING="yesterday_marathons"
  fi
fi

# Initialize session state
NOW=$(date +%s)
jq -n --arg sid "$SESSION_ID" --argjson ts "$NOW" --arg warn "$MARATHON_WARNING" '{
  session_id: $sid,
  start_ts: $ts,
  prompt_count: 0,
  full_breaks: 0,
  quick_breaks: 0,
  last_break_ts: $ts,
  last_full_break_ts: null,
  last_quick_break_ts: null,
  last_nudge_ts: 0,
  nudge_pending: false,
  nudge_tier: null,
  nudge_ignored_count: 0,
  intention: null,
  pattern_warning: $warn
}' > "$SESSION_FILE"
