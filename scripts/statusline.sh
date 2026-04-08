#!/bin/bash
# Breather status line -- session + daily fatigue indicator
# Format: breather  session: 45m | today: 3h 12m | 1 break
#
# Session time is informational (dim). Daily total is the fatigue number (colored).
# If nudges are being ignored: "take a break" replaces break count.
# If break commitment expired: "break time" replaces break count.

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

stdin_data=$(cat)

# Break count always shown (removed configurable options for simplicity)

# --- Session time (this conversation) ---
# Find current session by most recently active file
SESSION_FILE="$(breather_find_current_session)"

NOW=$(date +%s)
session_hours=0
session_minutes=0

if [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ]; then
  START_TS=$(jq -r '.start_ts // 0' "$SESSION_FILE" 2>/dev/null)
  if [ "$START_TS" -gt 0 ] 2>/dev/null && ! breather_is_stale "$START_TS"; then
    session_sec=$((NOW - START_TS))
    session_hours=$((session_sec / 3600))
    session_minutes=$(((session_sec % 3600) / 60))
  fi
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

# --- Global daily stats ---
GLOBAL=$(breather_read_all_sessions 2>/dev/null || echo '{}')
TODAY_TOTAL_MIN=$(echo "$GLOBAL" | jq -r '.today_total_min // 0' 2>/dev/null)
: "${TODAY_TOTAL_MIN:=0}"
SINCE_BREAK_MIN=$(echo "$GLOBAL" | jq -r '.since_last_break_min // 0' 2>/dev/null)
: "${SINCE_BREAK_MIN:=0}"
FULL_BREAKS=$(echo "$GLOBAL" | jq -r '.full_breaks // 0' 2>/dev/null)
: "${FULL_BREAKS:=0}"
QUICK_BREAKS=$(echo "$GLOBAL" | jq -r '.quick_breaks // 0' 2>/dev/null)
: "${QUICK_BREAKS:=0}"
ANY_NUDGE_IGNORED=$(echo "$GLOBAL" | jq -r '.any_nudge_ignored // false' 2>/dev/null)
BREAK_COMMITTED_AT=$(echo "$GLOBAL" | jq -r '.break_committed_at // "null"' 2>/dev/null)
BREAK_COMMITTED_MIN=$(echo "$GLOBAL" | jq -r '.break_committed_min // "null"' 2>/dev/null)

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
# breather Xm · Xh Ym today · N breaks + N stretches
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

if [ "$ANY_NUDGE_IGNORED" = "true" ]; then
  printf '%b\033[33mtake a break\033[0m' "$SEP"
elif [ "$SHOW_BREAK_TIME" = "true" ]; then
  printf '%b\033[33mbreak time\033[0m' "$SEP"
elif [ "$FULL_BREAKS" -gt 0 ] || [ "$QUICK_BREAKS" -gt 0 ]; then
  if [ "$FULL_BREAKS" -gt 0 ] && [ "$QUICK_BREAKS" -gt 0 ]; then
    printf '%b\033[37m%d break%s · %d stretch%s\033[0m' "$SEP" "$FULL_BREAKS" "$([ "$FULL_BREAKS" -ne 1 ] && echo 's')" "$QUICK_BREAKS" "$([ "$QUICK_BREAKS" -ne 1 ] && echo 'es')"
  elif [ "$FULL_BREAKS" -gt 0 ]; then
    printf '%b\033[37m%d break%s\033[0m' "$SEP" "$FULL_BREAKS" "$([ "$FULL_BREAKS" -ne 1 ] && echo 's')"
  else
    printf '%b\033[37m%d stretch%s\033[0m' "$SEP" "$QUICK_BREAKS" "$([ "$QUICK_BREAKS" -ne 1 ] && echo 'es')"
  fi
fi
