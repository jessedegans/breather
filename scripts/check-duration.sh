#!/bin/bash
# Called by UserPromptSubmit hook -- tracks prompts, detects inactivity, emits nudges
# Philosophy: AI-assisted coding removes natural speed limits. We put them back.
#
# Nudge delivery strategy (escalating hybrid):
#   Level 1 (suffix): "After answering, end with..." -- natural, ~85% compliance
#   Level 2 (prefix): "Start your response with..." -- structural, ~92% compliance
#   Level 3 (statusline): bypass Claude entirely -- 100% delivery
# Escalation driven by nudge_ignored_count (0 = suffix, 1 = prefix, 2+ = statusline).
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
    # Increment counter in current session only, reset fatigue in ALL sessions.
    SESSIONS_DIR="$(breather_sessions_dir)"
    if compgen -G "$SESSIONS_DIR/*.json" > /dev/null 2>&1; then
      for f in "$SESSIONS_DIR"/*.json; do
        local_prompt_ts=$(jq -r '.last_prompt_ts // 0' "$f" 2>/dev/null)
        if ! breather_is_stale "$local_prompt_ts"; then
          if [ "$f" = "$SESSION_FILE" ]; then
            jq ".full_breaks = (.full_breaks // 0) + 1 | .last_break_ts = $NOW | .last_full_break_ts = $NOW" \
              "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
          else
            jq ".last_break_ts = $NOW" \
              "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
          fi
        fi
      done
    fi
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

# Velocity alarm: 5+ prompts/min sustained (stays integrated, not suffix/prefix)
if [ "$VELOCITY" -ge 5 ] && [ "$ELAPSED_MIN" -ge 10 ]; then
  TIER="velocity"
  NUDGE='{"systemMessage": "[breather] '"$NEW_COUNT"' prompts in '"$ELAPSED_MIN"'min ('"$VELOCITY"'/min). Weave this into your response naturally: pause, restate what you are actually trying to accomplish, and ask if this is still the right direction."}'

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
  jq ".last_nudge_ts = $NOW | .nudge_pending = true | .nudge_tier = \"$TIER\"" \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  echo "$NUDGE"
fi
