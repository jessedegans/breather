#!/bin/bash
# Breather status line -- session + daily fatigue indicator
# Format: breather  0h 45m · 3h 12m today · last break: 32m ago
#
# Reads state.json (one file, no aggregation needed).
# Session time from sessions map. Daily total from counters.
# Color: green < 50m, yellow 50-90m, red 90m+ since last break.

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

stdin_data=$(cat)

# --- Read state ---
STATE=$(breather_read_state 2>/dev/null)
if [ -z "$STATE" ] || [ "$STATE" = "{}" ]; then
  printf '\033[2mbreather 0h 0m\033[0m'
  exit 0
fi

NOW=$(date +%s)

# --- Session time (this conversation) ---
# Find current session by most recent last_prompt_ts in sessions map
SESSION_START=$(echo "$STATE" | jq -r '
  [.sessions // {} | to_entries[] | .value] | sort_by(.last_prompt_ts) | last // null | .start_ts // 0
')

session_hours=0
session_minutes=0

if [ "$SESSION_START" -gt 0 ] 2>/dev/null; then
  session_sec=$((NOW - SESSION_START))
  session_hours=$((session_sec / 3600))
  session_minutes=$(((session_sec % 3600) / 60))
else
  # Fallback: Claude Code's cumulative timer
  duration_ms=$(echo "$stdin_data" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
  : "${duration_ms:=0}"
  if [ "$duration_ms" -gt 0 ] 2>/dev/null; then
    total_sec=$((duration_ms / 1000))
    session_hours=$((total_sec / 3600))
    session_minutes=$(((total_sec % 3600) / 60))
  fi
fi

# --- Global stats from state.json ---
SINCE_BREAK_MIN=$(breather_since_last_break_min "$STATE")
TODAY_TOTAL_MIN=$(breather_today_total_min "$STATE")
FULL_BREAKS=$(echo "$STATE" | jq -r '.counters.full_breaks // 0')
QUICK_BREAKS=$(echo "$STATE" | jq -r '.counters.quick_breaks // 0')
NUDGE_IGNORED=$(echo "$STATE" | jq -r '.nudge.ignored_count // 0')
BREAK_COMMITTED_AT=$(echo "$STATE" | jq -r '.commitment.break_committed_at // "null"')
BREAK_COMMITTED_MIN=$(echo "$STATE" | jq -r '.commitment.break_committed_min // "null"')

today_hours=$((TODAY_TOTAL_MIN / 60))
today_minutes=$((TODAY_TOTAL_MIN % 60))

# --- Daily total color (the fatigue indicator) ---
if [ "$SINCE_BREAK_MIN" -ge 90 ]; then
  today_color='\033[31m'  # Red
elif [ "$SINCE_BREAK_MIN" -ge 50 ]; then
  today_color='\033[33m'  # Yellow
else
  today_color='\033[32m'  # Green
fi

SEP='\033[2m · \033[0m'

# --- Build the line ---
printf '\033[2mbreather %dh %dm\033[0m' "$session_hours" "$session_minutes"
printf '%b%b%dh %dm today\033[0m' "$SEP" "$today_color" "$today_hours" "$today_minutes"

# --- Right-side: break count OR status message ---
# Check for break commitment expired
SHOW_BREAK_TIME=false
if [ "$BREAK_COMMITTED_AT" != "null" ] && [ "$BREAK_COMMITTED_MIN" != "null" ]; then
  BREAK_DUE_AT=$((BREAK_COMMITTED_AT + BREAK_COMMITTED_MIN * 60))
  if [ "$NOW" -ge "$BREAK_DUE_AT" ]; then
    SHOW_BREAK_TIME=true
  fi
fi

ANY_NUDGE_IGNORED=false
if [ "$NUDGE_IGNORED" -ge 2 ]; then
  ANY_NUDGE_IGNORED=true
fi

if [ "$ANY_NUDGE_IGNORED" = "true" ]; then
  # Level 3 bypass: color matches fatigue tier
  if [ "$SINCE_BREAK_MIN" -ge 90 ]; then
    printf '%b\033[31mtake a break\033[0m' "$SEP"
  else
    printf '%b\033[33mtake a break\033[0m' "$SEP"
  fi
elif [ "$SHOW_BREAK_TIME" = "true" ]; then
  printf '%b\033[33mbreak time\033[0m' "$SEP"
elif [ "$SINCE_BREAK_MIN" -ge 25 ]; then
  # When fatigue starts mattering, show time since last break (actionable)
  printf '%b\033[2mlast break: %dm ago\033[0m' "$SEP" "$SINCE_BREAK_MIN"
elif [ "$FULL_BREAKS" -gt 0 ] || [ "$QUICK_BREAKS" -gt 0 ]; then
  # Otherwise show break count
  if [ "$FULL_BREAKS" -gt 0 ] && [ "$QUICK_BREAKS" -gt 0 ]; then
    printf '%b\033[37m%d break%s · %d stretch%s\033[0m' "$SEP" "$FULL_BREAKS" "$([ "$FULL_BREAKS" -ne 1 ] && echo 's')" "$QUICK_BREAKS" "$([ "$QUICK_BREAKS" -ne 1 ] && echo 'es')"
  elif [ "$FULL_BREAKS" -gt 0 ]; then
    printf '%b\033[37m%d break%s\033[0m' "$SEP" "$FULL_BREAKS" "$([ "$FULL_BREAKS" -ne 1 ] && echo 's')"
  else
    printf '%b\033[37m%d stretch%s\033[0m' "$SEP" "$QUICK_BREAKS" "$([ "$QUICK_BREAKS" -ne 1 ] && echo 'es')"
  fi
fi
