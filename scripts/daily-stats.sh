#!/bin/bash
# Output daily stats as JSON. Called by skills that need global session data.
# Usage: bash ${CLAUDE_PLUGIN_ROOT}/scripts/daily-stats.sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

STATE=$(breather_read_state)
NOW=$(date +%s)

SINCE_BREAK_MIN=$(breather_since_last_break_min "$STATE")
TODAY_TOTAL_MIN=$(breather_today_total_min "$STATE")

FULL_BREAKS=$(echo "$STATE" | jq -r '.counters.full_breaks // 0')
QUICK_BREAKS=$(echo "$STATE" | jq -r '.counters.quick_breaks // 0')
PROMPT_COUNT=$(echo "$STATE" | jq -r '.counters.prompt_count // 0')
ACTIVE_SESSIONS=$(echo "$STATE" | jq '[.sessions // {} | keys[]] | length')

jq -n \
  --argjson ttm "$TODAY_TOTAL_MIN" \
  --argjson slbm "$SINCE_BREAK_MIN" \
  --argjson fb "$FULL_BREAKS" \
  --argjson qb "$QUICK_BREAKS" \
  --argjson tp "$PROMPT_COUNT" \
  --argjson as "$ACTIVE_SESSIONS" \
  '{
    today_total_min: $ttm,
    since_last_break_min: $slbm,
    full_breaks: $fb,
    quick_breaks: $qb,
    total_prompts: $tp,
    active_sessions: $as
  }'
