#!/bin/bash
# Breather status line -- single-line session indicator
# Intentionally minimal: only shows what breather uniquely knows.
# Won't conflict with other statusline plugins (model, git, cost, context).
#
# Configurable via plugin userConfig:
#   show_prompt_count  - show prompt count (default: false)
#   show_velocity      - show prompts/min rate (default: false)
#   show_break_count   - show break count (default: true)

stdin_data=$(cat)

# User-configurable options (via CLAUDE_PLUGIN_OPTION_* env vars)
SHOW_PROMPT_COUNT="${CLAUDE_PLUGIN_OPTION_SHOW_PROMPT_COUNT:-false}"
SHOW_VELOCITY="${CLAUDE_PLUGIN_OPTION_SHOW_VELOCITY:-false}"
SHOW_BREAK_COUNT="${CLAUDE_PLUGIN_OPTION_SHOW_BREAK_COUNT:-true}"

# Session duration from Claude Code
duration_ms=$(echo "$stdin_data" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
: "${duration_ms:=0}"

if [ "$duration_ms" -le 0 ] 2>/dev/null; then
    exit 0
fi

total_sec=$((duration_ms / 1000))
hours=$((total_sec / 3600))
minutes=$(((total_sec % 3600) / 60))
elapsed_min=$((total_sec / 60))

# Breather session state
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"
FULL_BREAKS=0
QUICK_BREAKS=0
PROMPT_COUNT=0
SINCE_BREAK_MIN=0

if [ -f "$SESSION_FILE" ]; then
    IFS=$'\t' read -r FULL_BREAKS QUICK_BREAKS LAST_BREAK_TS PROMPT_COUNT < <(
        jq -r '[(.full_breaks // 0), (.quick_breaks // 0), (.last_break_ts // 0), (.prompt_count // 0)] | @tsv' \
        "$SESSION_FILE" 2>/dev/null
    )
    : "${FULL_BREAKS:=0}"
    : "${QUICK_BREAKS:=0}"
    : "${LAST_BREAK_TS:=0}"
    : "${PROMPT_COUNT:=0}"
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

SEP='\033[2m|\033[0m'

# Always show: colored session timer
printf '%b%dh %dm\033[0m' "$color" "$hours" "$minutes"

# Optional: break count
if [ "$SHOW_BREAK_COUNT" = "true" ]; then
    TOTAL_BREAKS=$((FULL_BREAKS + QUICK_BREAKS))
    if [ "$TOTAL_BREAKS" -gt 0 ]; then
        printf ' %b \033[37m%d+%d\033[0m' "$SEP" "$FULL_BREAKS" "$QUICK_BREAKS"
    fi
fi

# Optional: prompt count
if [ "$SHOW_PROMPT_COUNT" = "true" ] && [ "$PROMPT_COUNT" -gt 0 ] 2>/dev/null; then
    printf ' %b \033[37m%d prompts\033[0m' "$SEP" "$PROMPT_COUNT"
fi

# Optional: velocity (prompts/min)
if [ "$SHOW_VELOCITY" = "true" ] && [ "$elapsed_min" -gt 0 ] 2>/dev/null; then
    velocity=$((PROMPT_COUNT / elapsed_min))
    if [ "$velocity" -ge 5 ]; then
        # Red velocity -- reactive mode
        printf ' %b \033[31m%d/min\033[0m' "$SEP" "$velocity"
    elif [ "$velocity" -ge 2 ]; then
        printf ' %b \033[37m%d/min\033[0m' "$SEP" "$velocity"
    fi
fi
