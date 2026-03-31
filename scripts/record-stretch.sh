#!/bin/bash
# Called when user takes a quick stretch break -- partial fatigue reset
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"

[ -f "$SESSION_FILE" ] || exit 0

NOW=$(date +%s)
# Advance last_break_ts by 10 minutes (partial reset, not full)
# This gives ~10 more minutes before the next nudge tier kicks in
PARTIAL_RESET=$((NOW - $(jq -r '.last_break_ts' "$SESSION_FILE") ))
if [ "$PARTIAL_RESET" -gt 600 ]; then
  # Only advance by 10 min worth, don't fully reset
  NEW_BREAK_TS=$(( $(jq -r '.last_break_ts' "$SESSION_FILE") + 600 ))
else
  NEW_BREAK_TS=$(jq -r '.last_break_ts' "$SESSION_FILE")
fi

jq ".quick_breaks = (.quick_breaks // 0) + 1 | .last_quick_break_ts = $NOW | .last_break_ts = $NEW_BREAK_TS" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
