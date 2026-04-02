#!/bin/bash
# Called by SessionEnd hook -- archives session to history, cleans up
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
export BREATHER_SESSION_ID

SESSION_FILE="$(breather_session_file "$BREATHER_SESSION_ID")"
HISTORY_FILE="$(breather_history_file)"

[ -f "$SESSION_FILE" ] || exit 0

START_TS=$(jq -r '.start_ts // 0' "$SESSION_FILE")
NOW=$(date +%s)
ELAPSED_MIN=$(( (NOW - START_TS) / 60 ))

# Only log sessions with meaningful duration (> 1 min)
if [ "$ELAPSED_MIN" -gt 1 ]; then
  jq -c ". + {end_ts: $NOW, duration_min: $ELAPSED_MIN, date: \"$(date -Iseconds)\"}" \
    "$SESSION_FILE" >> "$HISTORY_FILE"
fi

# Clean up session file
rm -f "$SESSION_FILE"
