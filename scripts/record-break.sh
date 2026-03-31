#!/bin/bash
# Called when user takes a full break -- updates session state, fully resets fatigue clock
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"

[ -f "$SESSION_FILE" ] || exit 0

NOW=$(date +%s)
jq ".full_breaks = (.full_breaks // 0) + 1 | .last_break_ts = $NOW | .last_full_break_ts = $NOW" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
