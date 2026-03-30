#!/bin/bash
# Breather status line — always-visible session timer with color coding
# Receives session JSON via stdin from Claude Code

INPUT=$(cat)

DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
DURATION_MIN=$((DURATION_MS / 60000))
HOURS=$((DURATION_MIN / 60))
MINS=$((DURATION_MIN % 60))

# Read break count from state
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"
BREAKS=0
if [ -f "$SESSION_FILE" ]; then
  BREAKS=$(jq -r '.breaks_taken // 0' "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Color thresholds (ANSI)
if [ "$DURATION_MIN" -ge 180 ]; then
  # Red — you really need a break
  printf '\033[31m%dh %dm\033[0m' "$HOURS" "$MINS"
elif [ "$DURATION_MIN" -ge 90 ]; then
  # Yellow — getting long
  printf '\033[33m%dh %dm\033[0m' "$HOURS" "$MINS"
else
  # Green — you're fine
  printf '\033[32m%dh %dm\033[0m' "$HOURS" "$MINS"
fi

if [ "$BREAKS" -gt 0 ]; then
  printf ' | breaks: %d' "$BREAKS"
fi
