#!/bin/bash
# Called when user takes a quick stretch -- partial fatigue reset (+10 min)
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Try to get session_id from stdin, fall back to env
INPUT=$(cat 2>/dev/null || echo '{}')
BREATHER_SESSION_ID="${BREATHER_SESSION_ID:-$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)}"
export BREATHER_SESSION_ID

SESSION_FILE="$(breather_ensure_session "$BREATHER_SESSION_ID")"
NOW=$(date +%s)

# Partial reset: advance last_break_ts by 10 minutes (600 sec)
CURRENT_BREAK_TS=$(jq -r '.last_break_ts // 0' "$SESSION_FILE")
NEW_BREAK_TS=$((CURRENT_BREAK_TS + 600))
if [ "$NEW_BREAK_TS" -gt "$NOW" ]; then
  NEW_BREAK_TS=$NOW
fi

jq ".quick_breaks = (.quick_breaks // 0) + 1 | .last_quick_break_ts = $NOW | .last_break_ts = $NEW_BREAK_TS" \
  "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
