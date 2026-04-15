#!/bin/bash
# Called by SessionStart hook -- creates session, migrates data, checks patterns
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Run migrations (v1 -> v2 -> v3)
breather_migrate_v1
breather_migrate_v2_to_v3

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
export BREATHER_SESSION_ID

NOW=$(date +%s)
HISTORY_FILE="$(breather_history_file)"

# Ensure state.json exists
breather_init_state

# Day reset check
breather_check_day_reset

# Clean stale sessions from state.json and archive them
STATE=$(breather_read_state)
STALE_SIDS=$(echo "$STATE" | jq -r --argjson cutoff "$((NOW - 28800))" '
  .sessions // {} | to_entries[]
  | select(.value.last_prompt_ts <= $cutoff)
  | .key
' 2>/dev/null || true)

if [ -n "$STALE_SIDS" ]; then
  for sid in $STALE_SIDS; do
    # Archive to history if meaningful
    local_start=$(echo "$STATE" | jq -r --arg s "$sid" '.sessions[$s].start_ts // 0')
    local_last_prompt=$(echo "$STATE" | jq -r --arg s "$sid" '.sessions[$s].last_prompt_ts // 0')
    local_elapsed=$(( (local_last_prompt - local_start) / 60 ))
    if [ "$local_elapsed" -gt 1 ]; then
      jq -n -c --arg sid "$sid" --argjson start "$local_start" --argjson end "$local_last_prompt" \
        --argjson dur "$local_elapsed" --arg date "$(date -Iseconds)" \
        '{session_id: $sid, start_ts: $start, end_ts: $end, duration_min: $dur, date: $date}' \
        >> "$HISTORY_FILE"
    fi
    # Remove session pointer file
    rm -f "$(breather_session_file "$sid")"
  done

  # Remove stale entries from state.json
  breather_update_state --argjson cutoff "$((NOW - 28800))" '
    .sessions |= with_entries(select(.value.last_prompt_ts > $cutoff))
  ' > /dev/null
fi

# Don't overwrite if this session already exists and is active
EXISTING_LP=$(echo "$STATE" | jq -r --arg s "$BREATHER_SESSION_ID" '.sessions[$s].last_prompt_ts // 0')
if [ "$EXISTING_LP" -gt 0 ] 2>/dev/null && ! breather_is_stale "$EXISTING_LP"; then
  exit 0
fi

# Check yesterday's patterns
MARATHON_WARNING=""
if [ -f "$HISTORY_FILE" ]; then
  YESTERDAY=$(date -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s 2>/dev/null || echo 0)
  LONG_SESSIONS=$(jq -s "[.[] | select(.end_ts > $YESTERDAY and (.duration_min // 0) > 90)] | length" "$HISTORY_FILE" 2>/dev/null || echo 0)
  if [ "$LONG_SESSIONS" -ge 2 ]; then
    MARATHON_WARNING="yesterday_marathons"
  fi
fi

# Register session in state.json
breather_update_state --arg sid "$BREATHER_SESSION_ID" --argjson now "$NOW" '
  .sessions[$sid] = {start_ts: $now, last_prompt_ts: $now} |
  if .fatigue.earliest_active_ts == 0 or .fatigue.earliest_active_ts > $now then
    .fatigue.earliest_active_ts = $now
  else . end
' > /dev/null

# Create slim session pointer file
jq -n --arg sid "$BREATHER_SESSION_ID" --argjson ts "$NOW" '{
  session_id: $sid,
  start_ts: $ts,
  last_prompt_ts: $ts,
  prompt_count: 0
}' > "$(breather_session_file "$BREATHER_SESSION_ID")"

# Output context for Claude
if [ "$MARATHON_WARNING" = "yesterday_marathons" ]; then
  echo "Breather session started. Yesterday had multiple long sessions. Be mindful of pacing today."
fi

# Check if setup has been run (mention once, then never again)
if ! grep -q 'breather' ~/.claude/settings.json 2>/dev/null; then
  MARKER="$(breather_state_dir)/.setup-prompted"
  if [ ! -f "$MARKER" ]; then
    echo "[breather] Run /breather:setup to add the status bar and auto-allow break recording."
    touch "$MARKER"
  fi
fi
