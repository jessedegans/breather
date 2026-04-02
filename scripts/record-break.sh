#!/bin/bash
# Called when user takes a full break -- fully resets fatigue clock
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Try to get session_id from stdin, fall back to env
INPUT=$(cat 2>/dev/null || echo '{}')
BREATHER_SESSION_ID="${BREATHER_SESSION_ID:-$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)}"
export BREATHER_SESSION_ID

SESSION_FILE="$(breather_ensure_session "$BREATHER_SESSION_ID")"
NOW=$(date +%s)

# Clear any break commitment
jq ".full_breaks = (.full_breaks // 0) + 1 | .last_break_ts = $NOW | .last_full_break_ts = $NOW | .break_committed_at = null | .break_committed_min = null | .nudge_ignored_count = 0" \
  "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
