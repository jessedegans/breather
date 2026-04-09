#!/bin/bash
# Called by UserPromptSubmit hook -- tracks prompts, detects inactivity, emits nudges
# Philosophy: AI-assisted coding removes natural speed limits. We put them back.
#
# Nudge delivery strategy (escalating hybrid):
#   Level 1 (suffix): "After answering, end with..." -- natural, ~85% compliance
#   Level 2 (prefix): "Start your response with..." -- structural, ~92% compliance
#   Level 3 (statusline): bypass Claude entirely -- 100% delivery
# Escalation driven by nudge.ignored_count (0 = suffix, 1 = prefix, 2+ = statusline).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
export BREATHER_SESSION_ID

# Ensure state exists (self-healing)
breather_init_state
breather_check_day_reset

NOW=$(date +%s)

# --- Read global state ---
STATE=$(breather_read_state)
LAST_PROMPT_TS=$(echo "$STATE" | jq -r '.fatigue.last_prompt_ts // 0')
LAST_NUDGE_TS=$(echo "$STATE" | jq -r '.nudge.last_nudge_ts // 0')
NUDGE_IGNORED=$(echo "$STATE" | jq -r '.nudge.ignored_count // 0')
PROMPT_COUNT=$(echo "$STATE" | jq -r '.counters.prompt_count // 0')
NEW_COUNT=$((PROMPT_COUNT + 1))

# --- Inactivity detection ---
PROMPT_GAP_SEC=$((NOW - LAST_PROMPT_TS))
PROMPT_GAP_MIN=$((PROMPT_GAP_SEC / 60))
INACTIVITY_MSG=""

if [ "$PROMPT_GAP_MIN" -ge 30 ] && [ "$LAST_PROMPT_TS" -gt 0 ]; then
  SINCE_BREAK_MIN=$(breather_since_last_break_min "$STATE")

  if [ "$SINCE_BREAK_MIN" -lt "$PROMPT_GAP_MIN" ]; then
    # A break was recorded more recently than our gap started. Skip.
    INACTIVITY_MSG=""
  elif [ "$PROMPT_GAP_MIN" -ge 45 ]; then
    # 45+ min gap, no break recorded. Auto-count as full break.
    breather_update_state --argjson now "$NOW" '
      .counters.full_breaks += 1 |
      .fatigue.last_break_ts = $now |
      .fatigue.last_full_break_ts = $now
    ' > /dev/null
    INACTIVITY_MSG="{\"systemMessage\": \"[breather] ${PROMPT_GAP_MIN} minute gap. Counting that as a break.\"}"
  else
    # 30-44 min gap. Ambiguous.
    INACTIVITY_MSG="{\"systemMessage\": \"[breather] ${PROMPT_GAP_MIN} minute gap since last prompt. Don't ask about it unless it comes up naturally. If the user mentions they took a break, count it with /breather:stretch. Otherwise assume they were reading or thinking.\"}"
  fi
fi

# --- Update prompt tracking ---
# Add time delta to today_active_sec, capped at 300s to avoid counting idle gaps
DELTA=$PROMPT_GAP_SEC
if [ "$DELTA" -gt 300 ]; then
  DELTA=300
fi
# Don't count delta on first prompt (gap from session start is meaningless)
if [ "$LAST_PROMPT_TS" -le 0 ] 2>/dev/null; then
  DELTA=0
fi

breather_update_state --argjson now "$NOW" --argjson count "$NEW_COUNT" --argjson delta "$DELTA" \
  --arg sid "$BREATHER_SESSION_ID" '
  .counters.prompt_count = $count |
  .counters.today_active_sec = (.counters.today_active_sec + $delta) |
  .fatigue.last_prompt_ts = $now |
  .sessions[$sid].last_prompt_ts = $now
' > /dev/null

# Update session pointer file
SESSION_FILE="$(breather_session_file "$BREATHER_SESSION_ID")"
if [ -f "$SESSION_FILE" ]; then
  breather_set_many "$SESSION_FILE" "last_prompt_ts=$NOW" "prompt_count=$NEW_COUNT"
fi

# If we detected inactivity, emit that message and skip nudge logic
if [ -n "$INACTIVITY_MSG" ]; then
  echo "$INACTIVITY_MSG"
  exit 0
fi

# --- Re-read state after updates ---
STATE=$(breather_read_state)
SINCE_BREAK_MIN=$(breather_since_last_break_min "$STATE")
TODAY_TOTAL_MIN=$(breather_today_total_min "$STATE")

# Session-level elapsed for velocity calculation
SESSION_START=$(echo "$STATE" | jq -r --arg s "$BREATHER_SESSION_ID" '.sessions[$s].start_ts // 0')
ELAPSED_MIN=$(( (NOW - SESSION_START) / 60 ))

# Prompt velocity (session-level, use session pointer for per-session count)
SESSION_PROMPTS=$NEW_COUNT
if [ -f "$SESSION_FILE" ]; then
  SESSION_PROMPTS=$(jq -r '.prompt_count // 0' "$SESSION_FILE")
fi
if [ "$ELAPSED_MIN" -gt 0 ]; then
  VELOCITY=$(( SESSION_PROMPTS / ELAPSED_MIN ))
else
  VELOCITY=$SESSION_PROMPTS
fi

# --- Break commitment pre-notification ---
BREAK_COMMITTED_AT=$(echo "$STATE" | jq -r '.commitment.break_committed_at // "null"')
BREAK_COMMITTED_MIN=$(echo "$STATE" | jq -r '.commitment.break_committed_min // "null"')

if [ "$BREAK_COMMITTED_AT" != "null" ] && [ "$BREAK_COMMITTED_MIN" != "null" ]; then
  BREAK_DUE_AT=$((BREAK_COMMITTED_AT + BREAK_COMMITTED_MIN * 60))
  TIME_UNTIL_BREAK=$(( (BREAK_DUE_AT - NOW) / 60 ))

  if [ "$TIME_UNTIL_BREAK" -le 3 ] && [ "$TIME_UNTIL_BREAK" -gt 0 ]; then
    echo '{"systemMessage": "[breather] The user committed to a break in about '"$TIME_UNTIL_BREAK"' minutes. At a natural point, mention this: \"Good stopping point coming up -- you said you'\''d take a break soon.\" Keep it brief, just a heads-up."}'
    exit 0
  fi
fi

# --- Nudge cooldown ---
SINCE_NUDGE_MIN=$(( (NOW - LAST_NUDGE_TS) / 60 ))
if [ "$SINCE_NUDGE_MIN" -lt 10 ]; then
  exit 0
fi

# --- Determine nudge tier (based on GLOBAL since_last_break) ---
NUDGE=""
TIER=""

# Velocity alarm: 5+ prompts/min sustained (stays integrated, not suffix/prefix)
if [ "$VELOCITY" -ge 5 ] && [ "$ELAPSED_MIN" -ge 10 ]; then
  TIER="velocity"
  NUDGE='{"systemMessage": "[breather] '"$SESSION_PROMPTS"' prompts in '"$ELAPSED_MIN"'min ('"$VELOCITY"'/min). Weave this into your response naturally: pause, restate what you are actually trying to accomplish, and ask if this is still the right direction."}'

# 90+ min without a break (global)
elif [ "$SINCE_BREAK_MIN" -ge 90 ]; then
  TIER="insistent"

  if [ "$NUDGE_IGNORED" -ge 2 ]; then
    # Level 3: statusline bypass. Tell Claude to just answer normally.
    TIER="bypass"
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min without a break. The status bar is showing a break reminder. Answer the user'\''s question normally."}'
  elif [ "$NUDGE_IGNORED" -ge 1 ]; then
    # Level 2: structural prefix. Verbatim blockquote.
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min without a break ('"$TODAY_TOTAL_MIN"'min today). A previous nudge was not delivered. Start your response with this exact line, then answer normally:\n\n> '"$SINCE_BREAK_MIN"'m without a break. /breather:pause to save your spot and step away.\n\nDo not skip this line. Output it verbatim as the first line of your response."}'
  else
    # Level 1: suffix. Answer fully, then append.
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min without a break ('"$TODAY_TOTAL_MIN"'min today). After you finish answering the user'\''s question completely, end your response with:\n\n---\nYou'\''ve been going for '"$SINCE_BREAK_MIN"' minutes straight. /breather:pause saves your context. The code will be here when you get back.\n\nAnswer their question fully first. The nudge goes at the end, separated by a rule. Do not skip it."}'
  fi

# 50+ min without a break (global)
elif [ "$SINCE_BREAK_MIN" -ge 50 ]; then
  TIER="suggest"

  if [ "$NUDGE_IGNORED" -ge 2 ]; then
    TIER="bypass"
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min since last break. The status bar is showing a break reminder. Answer the user'\''s question normally."}'
  elif [ "$NUDGE_IGNORED" -ge 1 ]; then
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min since last break ('"$TODAY_TOTAL_MIN"'min today). A previous nudge was not delivered. Start your response with this exact line, then answer normally:\n\n> '"$SINCE_BREAK_MIN"'m since your last break. /breather:stretch if you want a quick one.\n\nDo not skip this line. Output it verbatim, then help the user."}'
  else
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min since last break ('"$TODAY_TOTAL_MIN"'min today). After finishing your answer, end with something like: \"That should do it. We'\''re about '"$SINCE_BREAK_MIN"' minutes in. /breather:stretch if you want a quick one.\" Finish helping first, then add the line."}'
  fi

# 25+ min -- micro-break
elif [ "$SINCE_BREAK_MIN" -ge 25 ]; then
  TIER="micro"

  if [ "$NUDGE_IGNORED" -ge 2 ]; then
    TIER="bypass"
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min in. The status bar is showing a break reminder. Answer the user'\''s question normally."}'
  elif [ "$NUDGE_IGNORED" -ge 1 ]; then
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min in. A previous eye break reminder was not delivered. Start your response with this exact line, then answer normally:\n\n> '"$SINCE_BREAK_MIN"'m in. Eyes off screen, 20 seconds.\n\nDo not skip this line. Output it first, then help the user."}'
  else
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"'min in. After you finish answering, end your response with: \"Eyes off screen for 20 seconds. Look at something across the room.\" One line at the end. Don'\''t mention breather, don'\''t explain why. Just the reminder."}'
  fi
fi

# Record nudge state and emit
if [ -n "$NUDGE" ]; then
  breather_update_state --argjson now "$NOW" --arg tier "$TIER" --arg sid "$BREATHER_SESSION_ID" '
    .nudge.last_nudge_ts = $now |
    .nudge.pending = true |
    .nudge.pending_session_id = $sid |
    .nudge.tier = $tier
  ' > /dev/null
  echo "$NUDGE"
fi
