#!/bin/bash
# Called when user takes a break — updates session state
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"

[ -f "$SESSION_FILE" ] || exit 0

NOW=$(date +%s)
jq ".breaks_taken = .breaks_taken + 1 | .last_break_ts = $NOW" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
