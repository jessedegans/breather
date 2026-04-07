#!/bin/bash
# Called by SessionStart hook -- creates session file, archives stale sessions
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Run v1 migration if needed
breather_migrate_v1

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
export BREATHER_SESSION_ID

HISTORY_FILE="$(breather_history_file)"
SESSIONS_DIR="$(breather_sessions_dir)"

# Archive any stale session files to history before creating fresh state
NOW=$(date +%s)
if compgen -G "$SESSIONS_DIR/*.json" > /dev/null 2>&1; then
  for f in "$SESSIONS_DIR"/*.json; do
    local_start=$(jq -r '.start_ts // 0' "$f" 2>/dev/null)
    if breather_is_stale "$local_start"; then
      local_elapsed=$(( (NOW - local_start) / 60 ))
      if [ "$local_elapsed" -gt 1 ]; then
        jq -c ". + {end_ts: $NOW, duration_min: $local_elapsed, date: \"$(date -Iseconds)\"}" "$f" >> "$HISTORY_FILE"
      fi
      rm -f "$f"
    fi
  done
fi

# Check yesterday's patterns
MARATHON_WARNING=""
if [ -f "$HISTORY_FILE" ]; then
  YESTERDAY=$(date -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s 2>/dev/null || echo 0)
  LONG_SESSIONS=$(jq -s "[.[] | select(.end_ts > $YESTERDAY and .duration_min > 90)] | length" "$HISTORY_FILE" 2>/dev/null || echo 0)
  if [ "$LONG_SESSIONS" -ge 2 ]; then
    MARATHON_WARNING="yesterday_marathons"
  fi
fi

# Don't overwrite if check-duration.sh already bootstrapped this session
# But DO overwrite if the existing file is stale (e.g. from yesterday)
SESSION_FILE="$(breather_session_file "$BREATHER_SESSION_ID")"
if [ -f "$SESSION_FILE" ]; then
  existing_prompt_ts=$(jq -r '.last_prompt_ts // 0' "$SESSION_FILE" 2>/dev/null)
  if ! breather_is_stale "$existing_prompt_ts"; then
    exit 0
  fi
fi
jq -n --arg sid "$BREATHER_SESSION_ID" --argjson ts "$NOW" --arg warn "$MARATHON_WARNING" '{
  session_id: $sid,
  start_ts: $ts,
  prompt_count: 0,
  last_prompt_ts: $ts,
  full_breaks: 0,
  quick_breaks: 0,
  last_break_ts: $ts,
  last_full_break_ts: null,
  last_quick_break_ts: null,
  last_nudge_ts: 0,
  nudge_pending: false,
  nudge_tier: null,
  nudge_ignored_count: 0,
  break_committed_at: null,
  break_committed_min: null,
  intention: null,
  pattern_warning: $warn
}' > "$SESSION_FILE"

# Output context for Claude
if [ "$MARATHON_WARNING" = "yesterday_marathons" ]; then
  echo "Breather session started. Yesterday had multiple long sessions. Be mindful of pacing today."
fi

# Check if setup has been run (statusline configured = setup done)
if ! grep -q "breather-statusline" ~/.claude/settings.json 2>/dev/null; then
  echo "[breather] Plugin is installed but not set up yet. At a natural point early in the conversation, mention: \"Breather is installed but needs a quick setup. Run /breather:setup to configure the status line and auto-allow break recording.\" Keep it brief."
fi
