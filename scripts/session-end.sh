#!/bin/bash
# Called by SessionEnd hook — logs session to history
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"
HISTORY_FILE="$STATE_DIR/session-history.jsonl"

[ -f "$SESSION_FILE" ] || exit 0

START_TS=$(jq -r '.start_ts' "$SESSION_FILE")
NOW=$(date +%s)
ELAPSED_MIN=$(( (NOW - START_TS) / 60 ))

# Append session summary to history
jq -c ". + {end_ts: $NOW, duration_min: $ELAPSED_MIN, date: \"$(date -Iseconds)\"}" "$SESSION_FILE" >> "$HISTORY_FILE"

# Clean up current session
rm -f "$SESSION_FILE"
