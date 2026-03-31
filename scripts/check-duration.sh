#!/bin/bash
# Called by UserPromptSubmit hook -- tracks prompts and injects wellness nudges
# Philosophy: AI-assisted coding removes natural speed limits. We put them back.
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"

# Bootstrap: if session file doesn't exist, create it now
# (covers case where SessionStart hook didn't fire)
if [ ! -f "$SESSION_FILE" ]; then
  mkdir -p "$STATE_DIR"
  NOW=$(date +%s)
  jq -n --argjson ts "$NOW" '{
    session_id: "recovered",
    start_ts: $ts,
    prompt_count: 0,
    full_breaks: 0,
    quick_breaks: 0,
    last_break_ts: $ts,
    last_full_break_ts: null,
    last_quick_break_ts: null,
    last_nudge_ts: 0,
    intention: null,
    pattern_warning: ""
  }' > "$SESSION_FILE"
fi

START_TS=$(jq -r '.start_ts' "$SESSION_FILE")
PROMPT_COUNT=$(jq -r '.prompt_count' "$SESSION_FILE")
FULL_BREAKS=$(jq -r '.full_breaks // 0' "$SESSION_FILE")
LAST_BREAK_TS=$(jq -r '.last_break_ts' "$SESSION_FILE")
LAST_NUDGE_TS=$(jq -r '.last_nudge_ts // 0' "$SESSION_FILE")

NOW=$(date +%s)
ELAPSED_MIN=$(( (NOW - START_TS) / 60 ))
SINCE_BREAK_MIN=$(( (NOW - LAST_BREAK_TS) / 60 ))
SINCE_NUDGE_MIN=$(( (NOW - LAST_NUDGE_TS) / 60 ))
NEW_COUNT=$((PROMPT_COUNT + 1))

# --- Prompt velocity detection ---
# High velocity = rapid-fire prompts = high cognitive load
# Calculate prompts-per-minute over the session
if [ "$ELAPSED_MIN" -gt 0 ]; then
  VELOCITY=$(( NEW_COUNT / ELAPSED_MIN ))
else
  VELOCITY=$NEW_COUNT
fi

# Update prompt count
jq ".prompt_count = $NEW_COUNT" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

# --- Nudge cooldown ---
# Don't spam: minimum 10 minutes between nudges
if [ "$SINCE_NUDGE_MIN" -lt 10 ]; then
  exit 0
fi

# --- Determine nudge ---
# Thresholds are deliberately aggressive. AI coding is cognitively intense --
# there's no compile time, no test suite running, no natural pause.
# We ARE the pause.

NUDGE=""

# Velocity alarm: 5+ prompts/min sustained = you're in reactive mode, not thinking
if [ "$VELOCITY" -ge 5 ] && [ "$ELAPSED_MIN" -ge 10 ]; then
  NUDGE='{"systemMessage": "[breather] '"$NEW_COUNT"' prompts in '"$ELAPSED_MIN"'min ('"$VELOCITY"'/min). The user is in rapid-fire mode - prompting faster than they can think. This is a sign of reactive coding, not deliberate work. In your next response, naturally weave in something like: \"We are moving fast - want to take a sec to make sure we are heading the right direction?\" Frame it as a quality check, not a wellness thing."}'

# 90+ min without a break -- insistent
elif [ "$SINCE_BREAK_MIN" -ge 90 ]; then
  NUDGE='{"systemMessage": "[breather] Session: '"$ELAPSED_MIN"'min total, '"$SINCE_BREAK_MIN"'min since last break, '"$NEW_COUNT"' prompts. Over 90 minutes without a break. AI-assisted work compresses hours of effort into minutes of wall-clock time - the brain does not get the recovery it needs. In your response, directly and clearly suggest a break. Say something like: \"You have been at this for '"$SINCE_BREAK_MIN"' minutes straight. Let me save your context - /breather:pause - and you can pick up right where you left off.\" Be direct. Not preachy, but do not bury it."}'

# 50+ min without a break -- suggest a real break
elif [ "$SINCE_BREAK_MIN" -ge 50 ]; then
  NUDGE='{"systemMessage": "[breather] Session: '"$ELAPSED_MIN"'min total, '"$SINCE_BREAK_MIN"'min since last break. 50+ minutes of continuous AI-assisted work. At a natural pause point in this response, mention the time: \"Been about '"$SINCE_BREAK_MIN"' minutes - good moment for a stretch if you want one. /breather:pause saves your spot.\" Keep it to one sentence, woven in naturally."}'

# 25+ min -- micro-break (20-20-20 rule)
elif [ "$SINCE_BREAK_MIN" -ge 25 ]; then
  NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min since last break. Quick micro-break moment: at the end of your response, add a brief line like \"Quick 20-20-20: look at something 20 feet away for 20 seconds.\" Only do this once - after this nudge, the next one will not come for at least 10 minutes."}'
fi

# Record nudge timestamp and emit
if [ -n "$NUDGE" ]; then
  jq ".last_nudge_ts = $NOW" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  echo "$NUDGE"
fi
