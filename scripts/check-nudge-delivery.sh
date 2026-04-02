#!/bin/bash
# Stop hook -- checks if Claude actually delivered the break nudge
# If nudge_pending is true but response lacks evidence, increment
# nudge_ignored_count for escalation (and eventually statusline bypass).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
export BREATHER_SESSION_ID

SESSION_FILE="$(breather_session_file "$BREATHER_SESSION_ID")"
[ -f "$SESSION_FILE" ] || exit 0

# Check if a nudge was pending
NUDGE_PENDING=$(jq -r '.nudge_pending // false' "$SESSION_FILE")
[ "$NUDGE_PENDING" = "true" ] || exit 0

NUDGE_TIER=$(jq -r '.nudge_tier // ""' "$SESSION_FILE")

# Read Claude's response
RESPONSE=$(echo "$INPUT" | jq -r '.assistant_response // .tool_result.content // ""' 2>/dev/null)

# If we can't read the response, clear pending and move on
if [ -z "$RESPONSE" ]; then
  jq '.nudge_pending = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  exit 0
fi

# Check for evidence that the nudge was delivered
DELIVERED=false

case "$NUDGE_TIER" in
  micro)
    if echo "$RESPONSE" | grep -qiE '6 meters|look away|eyes off|eye.?break|screen.?break'; then
      DELIVERED=true
    fi
    ;;
  suggest)
    if echo "$RESPONSE" | grep -qiE 'breather:(stretch|pause)|minutes.*break|break.*minutes|stretch.*if you want|good moment'; then
      DELIVERED=true
    fi
    ;;
  insistent|bypass)
    if echo "$RESPONSE" | grep -qiE 'breather:pause|take a break|step away|save.*(context|spot)|code will be here'; then
      DELIVERED=true
    fi
    ;;
  velocity)
    if echo "$RESPONSE" | grep -qiE 'right direction|slow.?down|moving fast|step back|heading.*right|pause.*think'; then
      DELIVERED=true
    fi
    ;;
esac

if [ "$DELIVERED" = "true" ]; then
  jq '.nudge_pending = false | .nudge_tier = null | .nudge_ignored_count = 0' \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
else
  IGNORED=$(jq -r '.nudge_ignored_count // 0' "$SESSION_FILE")
  NEW_IGNORED=$((IGNORED + 1))
  jq ".nudge_pending = false | .nudge_tier = null | .nudge_ignored_count = $NEW_IGNORED" \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
fi

exit 0
