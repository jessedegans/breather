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

# User-configurable options
SHOW_BREAK_COUNT="${CLAUDE_PLUGIN_OPTION_SHOW_BREAK_COUNT:-true}"

# --- Session time (this conversation) ---
# Try our own session file first, fall back to Claude Code's timer
BREATHER_SESSION_ID="${BREATHER_SESSION_ID:-unknown}"
SESSION_FILE="$(breather_session_file "$BREATHER_SESSION_ID")"

NOW=$(date +%s)
session_hours=0
session_minutes=0

if [ -f "$SESSION_FILE" ]; then
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
TOTAL_BREAKS=$(echo "$GLOBAL" | jq -r '.total_breaks // 0' 2>/dev/null)
: "${TOTAL_BREAKS:=0}"
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

SEP='\033[2m|\033[0m'

# --- Build the line ---
# breather  session: Xh Ym | today: Xh Ym | N breaks
printf '\033[2mbreather\033[0m  \033[2msession: %dh %dm\033[0m' "$session_hours" "$session_minutes"
printf ' %b %btoday: %dh %dm\033[0m' "$SEP" "$today_color" "$today_hours" "$today_minutes"

# --- Right-side: break count OR status message ---
if [ "$SHOW_BREAK_COUNT" = "true" ]; then
  # Check for break commitment expired
  SHOW_BREAK_TIME=false
  if [ "$BREAK_COMMITTED_AT" != "null" ] && [ "$BREAK_COMMITTED_MIN" != "null" ]; then
    BREAK_DUE_AT=$((BREAK_COMMITTED_AT + BREAK_COMMITTED_MIN * 60))
    if [ "$NOW" -ge "$BREAK_DUE_AT" ]; then
      SHOW_BREAK_TIME=true
    fi
  fi

  if [ "$ANY_NUDGE_IGNORED" = "true" ]; then
    # Nudges being ignored -- bypass Claude, talk to user directly
    printf ' %b \033[33mtake a break\033[0m' "$SEP"
  elif [ "$SHOW_BREAK_TIME" = "true" ]; then
    # Break commitment time passed
    printf ' %b \033[33mbreak time\033[0m' "$SEP"
  elif [ "$TOTAL_BREAKS" -gt 0 ]; then
    printf ' %b \033[37m%d break%s\033[0m' "$SEP" "$TOTAL_BREAKS" "$([ "$TOTAL_BREAKS" -ne 1 ] && echo 's')"
  fi
fi
