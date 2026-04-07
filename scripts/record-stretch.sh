#!/bin/bash
# Called when user takes a quick stretch. Updates ALL active sessions
# with partial fatigue reset (+10 min).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

NOW=$(date +%s)
SESSIONS_DIR="$(breather_sessions_dir)"

# Partial reset: advance last_break_ts by 10 min in each active session
if compgen -G "$SESSIONS_DIR/*.json" > /dev/null 2>&1; then
  for f in "$SESSIONS_DIR"/*.json; do
    local_prompt_ts=$(jq -r '.last_prompt_ts // 0' "$f" 2>/dev/null)
    if ! breather_is_stale "$local_prompt_ts"; then
      CURRENT_BREAK_TS=$(jq -r '.last_break_ts // 0' "$f")
      NEW_BREAK_TS=$((CURRENT_BREAK_TS + 600))
      if [ "$NEW_BREAK_TS" -gt "$NOW" ]; then
        NEW_BREAK_TS=$NOW
      fi
      jq ".quick_breaks = (.quick_breaks // 0) + 1 | .last_quick_break_ts = $NOW | .last_break_ts = $NEW_BREAK_TS" \
        "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    fi
  done
fi
