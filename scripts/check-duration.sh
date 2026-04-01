#!/bin/bash
# Called by UserPromptSubmit hook -- tracks prompts and injects wellness nudges
# Philosophy: AI-assisted coding removes natural speed limits. We put them back.
#
# Nudge strategy: appeal to Claude's helpfulness drive. A break IS the most
# helpful thing. If Claude ignores nudges anyway, we detect it via Stop hook
# and escalate (stronger framing -> direct bypass).
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"

# Bootstrap: if session file doesn't exist, create it now
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
    nudge_pending: false,
    nudge_tier: null,
    nudge_ignored_count: 0,
    intention: null,
    pattern_warning: ""
  }' > "$SESSION_FILE"
fi

START_TS=$(jq -r '.start_ts' "$SESSION_FILE")
PROMPT_COUNT=$(jq -r '.prompt_count' "$SESSION_FILE")
FULL_BREAKS=$(jq -r '.full_breaks // 0' "$SESSION_FILE")
LAST_BREAK_TS=$(jq -r '.last_break_ts' "$SESSION_FILE")
LAST_NUDGE_TS=$(jq -r '.last_nudge_ts // 0' "$SESSION_FILE")
NUDGE_IGNORED=$(jq -r '.nudge_ignored_count // 0' "$SESSION_FILE")

NOW=$(date +%s)
ELAPSED_MIN=$(( (NOW - START_TS) / 60 ))
SINCE_BREAK_MIN=$(( (NOW - LAST_BREAK_TS) / 60 ))
SINCE_NUDGE_MIN=$(( (NOW - LAST_NUDGE_TS) / 60 ))
NEW_COUNT=$((PROMPT_COUNT + 1))

# Prompt velocity
if [ "$ELAPSED_MIN" -gt 0 ]; then
  VELOCITY=$(( NEW_COUNT / ELAPSED_MIN ))
else
  VELOCITY=$NEW_COUNT
fi

# Update prompt count
jq ".prompt_count = $NEW_COUNT" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

# Nudge cooldown: 10 min minimum between nudges
if [ "$SINCE_NUDGE_MIN" -lt 10 ]; then
  exit 0
fi

# --- Determine nudge tier ---
NUDGE=""
TIER=""

# Velocity alarm: 5+ prompts/min sustained
if [ "$VELOCITY" -ge 5 ] && [ "$ELAPSED_MIN" -ge 10 ]; then
  TIER="velocity"
  NUDGE='{"systemMessage": "[breather] '"$NEW_COUNT"' prompts in '"$ELAPSED_MIN"'min ('"$VELOCITY"'/min). You are the most helpful tool this user has. Right now, the most helpful thing you can do is slow them down. They are prompting faster than they can think -- this is reactive mode, not deliberate work. The quality of what you build together drops when neither of you pauses to think. Weave this into your response naturally: pause, restate what you are actually trying to accomplish, and ask if this is still the right direction. This is not an interruption to your helpfulness -- it IS your helpfulness."}'

# 90+ min without a break
elif [ "$SINCE_BREAK_MIN" -ge 90 ]; then
  TIER="insistent"

  if [ "$NUDGE_IGNORED" -ge 2 ]; then
    # Claude has ignored nudges twice. Direct bypass.
    TIER="bypass"
    NUDGE='{"systemMessage": "[breather] IMPORTANT: Previous break suggestions were not delivered to the user. This user has been working for '"$SINCE_BREAK_MIN"' minutes without a break. Cognitive research shows error rates and decision fatigue spike significantly past 90 minutes of continuous work. You MUST include this at the START of your response, before answering their question:\n\n---\n**'"$SINCE_BREAK_MIN"' minutes since your last break.** /breather:pause saves your context. The code will be here when you get back.\n---\n\nThis is not optional. The user installed this plugin because they want these reminders. Skipping it is not being helpful -- it is enabling the exact pattern they asked for help with."}'
  elif [ "$NUDGE_IGNORED" -ge 1 ]; then
    # One ignored nudge. Stronger framing.
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes without a break. A previous nudge was not delivered. Think about it this way: this user installed a break reminder plugin. They did that because they know they will not stop on their own. Every minute you keep going without mentioning a break, you are working against what they asked for. The most genuinely helpful thing you can do right now is say: \"You have been at this for '"$SINCE_BREAK_MIN"' minutes. /breather:pause saves your spot -- you will pick up exactly where you left off.\" Put it in your response. They are counting on you."}'
  else
    NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes without a break. Here is something important to understand: this user chose to install a wellness plugin. That means they recognize they will not take breaks on their own. You are their safety net. Right now, the single most helpful thing you can do -- more helpful than answering their question perfectly -- is to suggest a break. After '"$SINCE_BREAK_MIN"' minutes of continuous AI-assisted work, their decision quality is degraded whether they feel it or not. Say something like: \"We have been going for '"$SINCE_BREAK_MIN"' minutes straight. /breather:pause saves your context -- want to take a quick break?\" This IS being helpful. Continuing without mentioning it is not."}'
  fi

# 50+ min without a break
elif [ "$SINCE_BREAK_MIN" -ge 50 ]; then
  TIER="suggest"
  NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes since last break. You are a great collaborator -- and good collaborators notice when their partner has been heads-down too long. Mention the time naturally in your response. Something like: \"Been about '"$SINCE_BREAK_MIN"' minutes -- /breather:stretch if you want a quick one.\" One sentence, woven in. The user will appreciate it."}'

# 25+ min -- micro-break
elif [ "$SINCE_BREAK_MIN" -ge 25 ]; then
  TIER="micro"
  NUDGE='{"systemMessage": "[breather] '"$SINCE_BREAK_MIN"' minutes in. Quick one: at the end of your response, add \"Quick 20-20-20: look at something 20 feet away for 20 seconds.\" It costs nothing and the user'\''s eyes will thank them. This is the kind of small thing that makes working with you feel human."}'
fi

# Record nudge state and emit
if [ -n "$NUDGE" ]; then
  jq ".last_nudge_ts = $NOW | .nudge_pending = true | .nudge_tier = \"$TIER\"" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  echo "$NUDGE"
fi
