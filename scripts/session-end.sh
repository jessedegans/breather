#!/bin/bash
# Called by SessionEnd hook -- archives session to history, removes from state
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
export BREATHER_SESSION_ID

STATE=$(breather_read_state)
HISTORY_FILE="$(breather_history_file)"

# Get session data from state.json
SESSION_START=$(echo "$STATE" | jq -r --arg s "$BREATHER_SESSION_ID" '.sessions[$s].start_ts // 0')
SESSION_LP=$(echo "$STATE" | jq -r --arg s "$BREATHER_SESSION_ID" '.sessions[$s].last_prompt_ts // 0')

# Archive to history if meaningful duration
if [ "$SESSION_START" -gt 0 ] 2>/dev/null; then
  ELAPSED_MIN=$(( (SESSION_LP - SESSION_START) / 60 ))
  if [ "$ELAPSED_MIN" -gt 1 ]; then
    # Get prompt count from session pointer if available
    SESSION_FILE="$(breather_session_file "$BREATHER_SESSION_ID")"
    PROMPT_COUNT=0
    if [ -f "$SESSION_FILE" ]; then
      PROMPT_COUNT=$(jq -r '.prompt_count // 0' "$SESSION_FILE")
    fi

    jq -n -c --arg sid "$BREATHER_SESSION_ID" --argjson start "$SESSION_START" \
      --argjson end "$SESSION_LP" --argjson dur "$ELAPSED_MIN" \
      --argjson pc "$PROMPT_COUNT" --arg date "$(date -Iseconds)" \
      '{session_id: $sid, start_ts: $start, end_ts: $end, duration_min: $dur, prompt_count: $pc, date: $date}' \
      >> "$HISTORY_FILE"
  fi
fi

# Remove session from state.json
breather_update_state --arg sid "$BREATHER_SESSION_ID" '
  .sessions |= del(.[$sid])
' > /dev/null

# Clean up session pointer file
rm -f "$(breather_session_file "$BREATHER_SESSION_ID")"
