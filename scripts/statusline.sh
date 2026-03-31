#!/bin/bash
# Breather status line -- always-visible session timer with color coding

INPUT=$(cat)

DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
DURATION_MIN=$((DURATION_MS / 60000))
HOURS=$((DURATION_MIN / 60))
MINS=$((DURATION_MIN % 60))

# Read break counts from state
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"
FULL_BREAKS=0
QUICK_BREAKS=0
if [ -f "$SESSION_FILE" ]; then
  FULL_BREAKS=$(jq -r '.full_breaks // 0' "$SESSION_FILE" 2>/dev/null || echo "0")
  QUICK_BREAKS=$(jq -r '.quick_breaks // 0' "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Color thresholds -- matched to nudge thresholds
if [ "$DURATION_MIN" -ge 90 ]; then
  # Red -- you really need a break
  printf '\033[31m%dh %dm\033[0m' "$HOURS" "$MINS"
elif [ "$DURATION_MIN" -ge 50 ]; then
  # Yellow -- break time soon
  printf '\033[33m%dh %dm\033[0m' "$HOURS" "$MINS"
else
  # Green -- you're fine
  printf '\033[32m%dh %dm\033[0m' "$HOURS" "$MINS"
fi

TOTAL_BREAKS=$((FULL_BREAKS + QUICK_BREAKS))
if [ "$TOTAL_BREAKS" -gt 0 ]; then
  printf ' | breaks: %d+%d' "$FULL_BREAKS" "$QUICK_BREAKS"
fi
