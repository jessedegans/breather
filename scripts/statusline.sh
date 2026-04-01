#!/bin/bash
# Breather status line -- single-line wellness indicator
# Intentionally minimal: only shows what breather uniquely knows.
# Won't conflict with other statusline plugins (model, git, cost, context).

stdin_data=$(cat)

# Session duration from Claude Code
duration_ms=$(echo "$stdin_data" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
: "${duration_ms:=0}"

if [ "$duration_ms" -le 0 ] 2>/dev/null; then
    exit 0
fi

total_sec=$((duration_ms / 1000))
hours=$((total_sec / 3600))
minutes=$(((total_sec % 3600) / 60))

# Breather session state
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"
FULL_BREAKS=0
QUICK_BREAKS=0
SINCE_BREAK_MIN=0

if [ -f "$SESSION_FILE" ]; then
    IFS=$'\t' read -r FULL_BREAKS QUICK_BREAKS LAST_BREAK_TS < <(
        jq -r '[(.full_breaks // 0), (.quick_breaks // 0), (.last_break_ts // 0)] | @tsv' \
        "$SESSION_FILE" 2>/dev/null
    )
    : "${FULL_BREAKS:=0}"
    : "${QUICK_BREAKS:=0}"
    : "${LAST_BREAK_TS:=0}"
    if [ "$LAST_BREAK_TS" -gt 0 ] 2>/dev/null; then
        NOW=$(date +%s)
        SINCE_BREAK_MIN=$(( (NOW - LAST_BREAK_TS) / 60 ))
    fi
fi

# Timer colored by time since last break (the fatigue clock)
if [ "$SINCE_BREAK_MIN" -ge 90 ]; then
    color='\033[31m'  # Red
elif [ "$SINCE_BREAK_MIN" -ge 50 ]; then
    color='\033[33m'  # Yellow
else
    color='\033[32m'  # Green
fi

# Format: colored timer | break count
SEP='\033[2m|\033[0m'
TOTAL_BREAKS=$((FULL_BREAKS + QUICK_BREAKS))

printf '%b%dh %dm\033[0m' "$color" "$hours" "$minutes"

if [ "$TOTAL_BREAKS" -gt 0 ]; then
    printf ' %b \033[37m%d+%d\033[0m' "$SEP" "$FULL_BREAKS" "$QUICK_BREAKS"
fi
