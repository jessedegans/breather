#!/bin/bash
# Called by UserPromptSubmit hook — tracks prompts and injects duration warnings
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"

# No state file = no tracking yet
[ -f "$SESSION_FILE" ] || exit 0

START_TS=$(jq -r '.start_ts' "$SESSION_FILE")
PROMPT_COUNT=$(jq -r '.prompt_count' "$SESSION_FILE")
BREAKS_TAKEN=$(jq -r '.breaks_taken' "$SESSION_FILE")
LAST_BREAK_TS=$(jq -r '.last_break_ts' "$SESSION_FILE")

NOW=$(date +%s)
ELAPSED_MIN=$(( (NOW - START_TS) / 60 ))
SINCE_BREAK_MIN=$(( (NOW - LAST_BREAK_TS) / 60 ))
NEW_COUNT=$((PROMPT_COUNT + 1))

# Update prompt count
jq ".prompt_count = $NEW_COUNT" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

# Determine if we should nudge — check every 10 prompts to avoid spam
if [ "$((NEW_COUNT % 10))" -ne 0 ]; then
  exit 0
fi

# Tiered nudging based on time since last break
if [ "$SINCE_BREAK_MIN" -ge 180 ]; then
  # 3+ hours without a break — direct
  echo '{"systemMessage": "[breather] Session: '"$ELAPSED_MIN"'min total, '"$SINCE_BREAK_MIN"'min since last break, '"$NEW_COUNT"' prompts. The user has been going for over 3 hours without a break. Research shows error rates spike significantly after 2h of continuous work. At the next natural pause point, directly suggest a break. Mention /pause to save their context. Do not be preachy — be matter-of-fact."}'
elif [ "$SINCE_BREAK_MIN" -ge 120 ]; then
  # 2+ hours — gentle but clear
  echo '{"systemMessage": "[breather] Session: '"$ELAPSED_MIN"'min total, '"$SINCE_BREAK_MIN"'min since last break, '"$NEW_COUNT"' prompts. Over 2 hours without a break. If you notice a natural pause point, briefly mention the session duration. Keep it to one sentence, woven into your response — not a separate callout."}'
elif [ "$SINCE_BREAK_MIN" -ge 90 ]; then
  # 90 min — subtle awareness
  echo '{"systemMessage": "[breather] Session: '"$ELAPSED_MIN"'min total, '"$SINCE_BREAK_MIN"'min since last break. 90+ minutes of continuous work. No action needed yet — just be aware."}'
fi
