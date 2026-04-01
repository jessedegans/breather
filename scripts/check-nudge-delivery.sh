#!/bin/bash
# Stop hook -- checks if Claude actually delivered the break nudge
# If nudge_pending is true but Claude's response doesn't contain evidence
# of the nudge, increment nudge_ignored_count for escalation next time.
set -euo pipefail

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
SESSION_FILE="$STATE_DIR/current-session.json"

[ -f "$SESSION_FILE" ] || exit 0

# Check if a nudge was pending
NUDGE_PENDING=$(jq -r '.nudge_pending // false' "$SESSION_FILE")
[ "$NUDGE_PENDING" = "true" ] || exit 0

NUDGE_TIER=$(jq -r '.nudge_tier // ""' "$SESSION_FILE")

# Read Claude's response from stdin
INPUT=$(cat)
RESPONSE=$(echo "$INPUT" | jq -r '.tool_result.content // .assistant_response // ""' 2>/dev/null)

# If we can't read the response, clear pending and move on
if [ -z "$RESPONSE" ]; then
  jq '.nudge_pending = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  exit 0
fi

# Check for evidence that the nudge was delivered
# Look for break-related keywords in Claude's response
DELIVERED=false

case "$NUDGE_TIER" in
  micro)
    # Look for 20-20-20 mention or any eye break reference
    if echo "$RESPONSE" | grep -qiE '20-20-20|20 feet|look away|eye.?break'; then
      DELIVERED=true
    fi
    ;;
  suggest)
    # Look for time mention + break suggestion
    if echo "$RESPONSE" | grep -qiE 'breather:(stretch|pause)|minutes.*break|break.*minutes|stretch.*if you want|good moment'; then
      DELIVERED=true
    fi
    ;;
  insistent|bypass)
    # Look for explicit break suggestion
    if echo "$RESPONSE" | grep -qiE 'breather:pause|take a break|step away|save.*(context|spot)|code will be here'; then
      DELIVERED=true
    fi
    ;;
  velocity)
    # Look for pace/direction check
    if echo "$RESPONSE" | grep -qiE 'right direction|slow.?down|moving fast|step back|heading.*right|pause.*think'; then
      DELIVERED=true
    fi
    ;;
esac

if [ "$DELIVERED" = "true" ]; then
  # Nudge was delivered -- reset counters
  jq '.nudge_pending = false | .nudge_tier = null | .nudge_ignored_count = 0' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
else
  # Nudge was ignored -- increment counter for escalation
  IGNORED=$(jq -r '.nudge_ignored_count // 0' "$SESSION_FILE")
  NEW_IGNORED=$((IGNORED + 1))
  jq ".nudge_pending = false | .nudge_tier = null | .nudge_ignored_count = $NEW_IGNORED" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
fi

exit 0
