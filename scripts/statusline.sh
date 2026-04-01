#!/bin/bash
# Breather status line -- two-line wellness-focused display
# Inspired by trailofbits/claude-code-config statusline pattern
#
# Line 1: [Model] folder | branch
# Line 2: Session timer (color-coded) | breaks | context bar | cost

stdin_data=$(cat)

# Single jq call -- extract all values at once for performance
IFS=$'\t' read -r current_dir model_name cost duration_ms ctx_used cache_pct < <(
    echo "$stdin_data" | jq -r '[
        .workspace.current_dir // "unknown",
        .model.display_name // "Unknown",
        (try (.cost.total_cost_usd // 0 | . * 100 | floor / 100) catch 0),
        (.cost.total_duration_ms // 0),
        (try (
            if (.context_window.remaining_percentage // null) != null then
                100 - (.context_window.remaining_percentage | floor)
            elif (.context_window.context_window_size // 0) > 0 then
                (((.context_window.current_usage.input_tokens // 0) +
                  (.context_window.current_usage.cache_creation_input_tokens // 0) +
                  (.context_window.current_usage.cache_read_input_tokens // 0)) * 100 /
                 .context_window.context_window_size) | floor
            else "null" end
        ) catch "null"),
        (try (
            (.context_window.current_usage // {}) |
            if (.input_tokens // 0) + (.cache_read_input_tokens // 0) > 0 then
                ((.cache_read_input_tokens // 0) * 100 /
                 ((.input_tokens // 0) + (.cache_read_input_tokens // 0))) | floor
            else 0 end
        ) catch 0)
    ] | @tsv'
)

# Fallback if jq crashed
if [ -z "$current_dir" ] && [ -z "$model_name" ]; then
    current_dir=$(echo "$stdin_data" | jq -r '.workspace.current_dir // "unknown"' 2>/dev/null)
    model_name=$(echo "$stdin_data" | jq -r '.model.display_name // "Unknown"' 2>/dev/null)
    cost=$(echo "$stdin_data" | jq -r '(.cost.total_cost_usd // 0)' 2>/dev/null)
    duration_ms=$(echo "$stdin_data" | jq -r '(.cost.total_duration_ms // 0)' 2>/dev/null)
    ctx_used=""
    cache_pct="0"
    : "${current_dir:=unknown}"
    : "${model_name:=Unknown}"
    : "${cost:=0}"
    : "${duration_ms:=0}"
fi

# Git info
if cd "$current_dir" 2>/dev/null; then
    git_branch=$(git -c core.useBuiltinFSMonitor=false branch --show-current 2>/dev/null)
    git_root=$(git -c core.useBuiltinFSMonitor=false rev-parse --show-toplevel 2>/dev/null)
fi

# Folder name (repo root or cwd basename)
if [ -n "$git_root" ]; then
    folder_name=$(basename "$git_root")
else
    folder_name=$(basename "$current_dir")
fi

# --- Breather session state ---
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"
FULL_BREAKS=0
QUICK_BREAKS=0
SINCE_BREAK_MIN=0

if [ -f "$SESSION_FILE" ]; then
    IFS=$'\t' read -r FULL_BREAKS QUICK_BREAKS LAST_BREAK_TS < <(
        jq -r '[
            (.full_breaks // 0),
            (.quick_breaks // 0),
            (.last_break_ts // 0)
        ] | @tsv' "$SESSION_FILE" 2>/dev/null
    )
    : "${FULL_BREAKS:=0}"
    : "${QUICK_BREAKS:=0}"
    : "${LAST_BREAK_TS:=0}"
    if [ "$LAST_BREAK_TS" -gt 0 ] 2>/dev/null; then
        NOW=$(date +%s)
        SINCE_BREAK_MIN=$(( (NOW - LAST_BREAK_TS) / 60 ))
    fi
fi

# --- Session timer (color-coded by time since last break) ---
if [ "$duration_ms" -gt 0 ] 2>/dev/null; then
    total_sec=$((duration_ms / 1000))
    hours=$((total_sec / 3600))
    minutes=$(((total_sec % 3600) / 60))

    if [ "$SINCE_BREAK_MIN" -ge 90 ]; then
        timer_color='\033[31m'  # Red -- you really need a break
    elif [ "$SINCE_BREAK_MIN" -ge 50 ]; then
        timer_color='\033[33m'  # Yellow -- break time soon
    else
        timer_color='\033[32m'  # Green -- you're fine
    fi
    session_time=$(printf '%b%dh %dm\033[0m' "$timer_color" "$hours" "$minutes")
else
    session_time=""
fi

# --- Context window progress bar ---
progress_bar=""
if [ -n "$ctx_used" ] && [ "$ctx_used" != "null" ]; then
    bar_width=10
    filled=$((ctx_used * bar_width / 100))
    empty=$((bar_width - filled))

    if [ "$ctx_used" -lt 50 ]; then
        bar_color='\033[32m'  # Green
    elif [ "$ctx_used" -lt 80 ]; then
        bar_color='\033[33m'  # Yellow
    else
        bar_color='\033[31m'  # Red
    fi

    progress_bar="${bar_color}"
    for ((i=0; i<filled; i++)); do
        progress_bar="${progress_bar}█"
    done
    progress_bar="${progress_bar}\033[2m"
    for ((i=0; i<empty; i++)); do
        progress_bar="${progress_bar}⣿"
    done
    progress_bar="${progress_bar}\033[0m ${ctx_used}%"
fi

# --- Separator ---
SEP='\033[2m|\033[0m'

# Short model name (e.g. "Opus" not "Claude 3.5 Opus")
short_model=$(echo "$model_name" | sed -E 's/Claude [0-9.]+ //; s/^Claude //')

# === LINE 1: [Model] folder | branch ===
line1=$(printf '\033[37m[%s]\033[0m \033[94m%s\033[0m' "$short_model" "$folder_name")
if [ -n "$git_branch" ]; then
    line1="$line1 $(printf '%b \033[96m%s\033[0m' "$SEP" "$git_branch")"
fi

# === LINE 2: timer | breaks | context bar | cost ===
line2=""

# Session timer (colored by fatigue)
if [ -n "$session_time" ]; then
    line2="$session_time"
fi

# Break count
TOTAL_BREAKS=$((FULL_BREAKS + QUICK_BREAKS))
if [ "$TOTAL_BREAKS" -gt 0 ]; then
    line2="$line2 $(printf '%b \033[37m%d+%d breaks\033[0m' "$SEP" "$FULL_BREAKS" "$QUICK_BREAKS")"
else
    line2="$line2 $(printf '%b \033[2mno breaks\033[0m' "$SEP")"
fi

# Context progress bar
if [ -n "$progress_bar" ]; then
    line2="$line2 $(printf '%b %b' "$SEP" "$progress_bar")"
fi

# Cost
line2="$line2 $(printf '%b \033[33m$%s\033[0m' "$SEP" "$cost")"

# Cache hit rate (if significant)
if [ "$cache_pct" -gt 0 ] 2>/dev/null; then
    line2="$line2$(printf ' \033[2m↻%s%%\033[0m' "$cache_pct")"
fi

printf '%b\n\n%b' "$line1" "$line2"
