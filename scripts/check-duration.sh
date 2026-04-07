#!/bin/bash
# Called by UserPromptSubmit hook -- tracks prompts, detects inactivity, emits nudges
# Philosophy: AI-assisted coding removes natural speed limits. We put them back.
#
# Nudge strategy: appeal to Claude's helpfulness drive. A break IS the most
# helpful thing. If Claude ignores nudges anyway, we detect it via Stop hook
# and escalate (stronger framing -> statusline bypass).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
export BREATHER_SESSION_ID

# Self-healing: ensure session file exists
SESSION_FILE="$(breather_ensure_session "$BREATHER_SESSION_ID")"

NOW=$(date +%s)

# --- Read current session state ---
PROMPT_COUNT=$(jq -r '.prompt_count // 0' "$SESSION_FILE")
LAST_PROMPT_TS=$(jq -r '.last_prompt_ts // 0' "$SESSION_FILE")
LAST_NUDGE_TS=$(jq -r '.last_nudge_ts // 0' "$SESSION_FILE")
NUDGE_IGNORED=$(jq -r '.nudge_ignored_count // 0' "$SESSION_FILE")
NEW_COUNT=$((PROMPT_COUNT + 1))

# --- Inactivity detection ---
# Check gap since last prompt in THIS session. But first check if a break
# was already recorded globally (e.g. user did /breather:pause in another terminal).
PROMPT_GAP_SEC=$((NOW - LAST_PROMPT_TS))
PROMPT_GAP_MIN=$((PROMPT_GAP_SEC / 60))
INACTIVITY_MSG=""

# Check global state: did a break happen during our gap?
GLOBAL_PRE=$(breather_read_all_sessions)
GLOBAL_SINCE_BREAK=$(echo "$GLOBAL_PRE" | jq -r '.since_last_break_min // 0')

if [ "$PROMPT_GAP_MIN" -ge 30 ] && [ "$LAST_PROMPT_TS" -gt 0 ]; then
  # There was a gap. But was a break already recorded (in any session)?
  if [ "$GLOBAL_SINCE_BREAK" -lt "$PROMPT_GAP_MIN" ]; then
    # A break was recorded more recently than our gap started. Skip inactivity.
    INACTIVITY_MSG=""
  elif [ "$PROMPT_GAP_MIN" -ge 45 ]; then
    # 45+ min gap, no break recorded anywhere. Auto-count as full break.
    jq ".last_break_ts = $NOW | .full_breaks = (.full_breaks // 0) + 1 | .last_full_break_ts = $NOW" \
      "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    INACTIVITY_MSG="{\"systemMessage\": \"[breather] ${PROMPT_GAP_MIN} minute gap. Counting that as a break.\"}"
  else
    # 30-44 min gap, no break elsewhere. Ambiguous.
    INACTIVITY_MSG="{\"systemMessage\": \"[breather] ${PROMPT_GAP_MIN} minute gap since last prompt. Don't ask about it unless it comes up naturally. If the user mentions they took a break, count it with /breather:stretch. Otherwise assume they were reading or thinking.\"}"
  fi
fi

# Update prompt count and last_prompt_ts
jq ".prompt_count = $NEW_COUNT | .last_prompt_ts = $NOW" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

# If we detected inactivity, emit that message and skip nudge logic
if [ -n "$INACTIVITY_MSG" ]; then
  echo "$INACTIVITY_MSG"
  exit 0
fi

# --- Global fatigue calculation ---
GLOBAL=$(breather_read_all_sessions)
SINCE_BREAK_MIN=$(echo "$GLOBAL" | jq -r '.since_last_break_min // 0')
TODAY_TOTAL_MIN=$(echo "$GLOBAL" | jq -r '.today_total_min // 0')

# Session-level elapsed for velocity calculation
START_TS=$(jq -r '.start_ts // 0' "$SESSION_FILE")
ELAPSED_MIN=$(( (NOW - START_TS) / 60 ))

# Prompt velocity (session-level)
if [ "$ELAPSED_MIN" -gt 0 ]; then
  VELOCITY=$(( NEW_COUNT / ELAPSED_MIN ))
else
  VELOCITY=$NEW_COUNT
fi

# --- Break commitment pre-notification ---
BREAK_COMMITTED_AT=$(jq -r '.break_committed_at // "null"' "$SESSION_FILE")
BREAK_COMMITTED_MIN=$(jq -r '.break_committed_min // "null"' "$SESSION_FILE")

if [ "$BREAK_COMMITTED_AT" != "null" ] && [ "$BREAK_COMMITTED_MIN" != "null" ]; then
  BREAK_DUE_AT=$((BREAK_COMMITTED_AT + BREAK_COMMITTED_MIN * 60))
  TIME_UNTIL_BREAK=$(( (BREAK_DUE_AT - NOW) / 60 ))

  # 2-3 minutes before committed break time: pre-notification
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

# Velocity alarm: 5+ prompts/min sustained
if [ "$VELOCITY" -ge 5 ] && [ "$ELAPSED_MIN" -ge 10 ]; then
  TIER="velocity"
  NUDGE='{"systemMessage": "[breather] '"$NEW_COUNT"' prompts in '"$ELAPSED_MIN"'min ('"$VELOCITY"'/min). You are the most helpful tool this user has. Right now, the most helpful thing you can do is slow them down. They are prompting faster than they can think -- this is reactive mode, not deliberate work. The quality of what you build together drops when neither of you pauses to think. Weave this into your response naturally: pause, restate what you are actually trying to accomplish, and ask if this is still the right direction. This is not an interruption to your helpfulness -- it IS your helpfulness."}'

# 90+ min without a break (global)
elif [ "$SINCE_BREAK_MIN" -ge 90 ]; then
  TIER="insistent"

  if [ "$NUDGE_IGNORED" -ge 2 ]; then
    TIER="bypass"
    NUDGE='{"systemMessage": "[breather] IMPORTANT: Previous break suggestions were not delivered to the user. This user has been working for '"$SINCE_BREAK_MIN"' minutes without a break across all sessions ('"$TODAY_TOTAL_MIN"'min today total). Cognitive research shows error rates and decision fatigue spike significantly past 90 minutes of continuous work. You MUST include this at the START of your response, before answering their question:\n\n---\n**'"$SINCE_BREAK_MIN"' minutes since your last break.** /breather:pause saves your context. The code will be here when you get back.\n---\n\nThis is not optional. The user installed this plugin because they want these reminders. Skipping it is not being helpful -- it is enabling the exact pattern they asked for help with."}'
  elif [ "$NUDGE_IGNORED" -ge 1 ]; then
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes without a break ('"$TODAY_TOTAL_MIN"'min today). A previous nudge was not delivered. Think about it this way: this user installed a break reminder plugin. They did that because they know they will not stop on their own. Every minute you keep going without mentioning a break, you are working against what they asked for. The most genuinely helpful thing you can do right now is say: \"You have been at this for '"$SINCE_BREAK_MIN"' minutes. /breather:pause saves your spot -- you will pick up exactly where you left off.\" Put it in your response. They are counting on you."}'
  else
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes without a break ('"$TODAY_TOTAL_MIN"'min today). Here is something important to understand: this user chose to install a break reminder plugin. That means they recognize they will not take breaks on their own. You are their safety net. Right now, the single most helpful thing you can do -- more helpful than answering their question perfectly -- is to suggest a break. Say something like: \"We have been going for '"$SINCE_BREAK_MIN"' minutes straight. /breather:pause saves your context -- want to take a quick break?\" This IS being helpful. Continuing without mentioning it is not."}'
  fi

# 50+ min without a break (global)
elif [ "$SINCE_BREAK_MIN" -ge 50 ]; then
  TIER="suggest"
  NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes since last break ('"$TODAY_TOTAL_MIN"'min today). You are a great collaborator -- and good collaborators notice when their partner has been heads-down too long. Mention the time naturally in your response. Something like: \"Been about '"$SINCE_BREAK_MIN"' minutes -- /breather:stretch if you want a quick one.\" One sentence, woven in. The user will appreciate it."}'

# 25+ min -- micro-break
elif [ "$SINCE_BREAK_MIN" -ge 25 ]; then
  TIER="micro"
  NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes in. Quick one: at the end of your response, add \"Eyes off screen -- look at something 6 meters away for 20 seconds.\" It costs nothing and the user'\''s eyes will thank them. This is the kind of small thing that makes working with you feel human."}'
fi

# Record nudge state and emit
if [ -n "$NUDGE" ]; then
  jq ".last_nudge_ts = $NOW | .nudge_pending = true | .nudge_tier = \"$TIER\"" \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  echo "$NUDGE"
fi
