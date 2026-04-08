#!/bin/bash
# Called when user takes a full break.
# Counter increments in current session only. Fatigue reset applies to all.
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

NOW=$(date +%s)
SESSIONS_DIR="$(breather_sessions_dir)"

# Find the most recently active session (where the break happened)
CURRENT="$(breather_find_current_session)"

if compgen -G "$SESSIONS_DIR/*.json" > /dev/null 2>&1; then
  for f in "$SESSIONS_DIR"/*.json; do
    local_prompt_ts=$(jq -r '.last_prompt_ts // 0' "$f" 2>/dev/null)
    if ! breather_is_stale "$local_prompt_ts"; then
      if [ "$f" = "$CURRENT" ]; then
        # Current session: increment counter + full reset + clear commitment
        jq ".full_breaks = (.full_breaks // 0) + 1 | .last_break_ts = $NOW | .last_full_break_ts = $NOW | .break_committed_at = null | .break_committed_min = null | .nudge_ignored_count = 0" \
          "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
      else
        # Other sessions: fatigue reset only
        jq ".last_break_ts = $NOW | .nudge_ignored_count = 0" \
          "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
      fi
    fi
  done
fi
