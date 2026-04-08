#!/bin/bash
# Stop hook -- checks if Claude actually delivered the break nudge.
# Position-aware detection:
#   Level 1 (suffix): check last 500 chars of response
#   Level 2 (prefix): check first 200 chars of response
#   Level 3 (bypass): no-op, statusline handles delivery
# If nudge wasn't delivered, increment nudge_ignored_count for escalation.
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
NUDGE_IGNORED=$(jq -r '.nudge_ignored_count // 0' "$SESSION_FILE")

# Level 3 (bypass): statusline handles it. Clear pending, done.
if [ "$NUDGE_IGNORED" -ge 2 ] || [ "$NUDGE_TIER" = "bypass" ]; then
  jq '.nudge_pending = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  exit 0
fi

# Read Claude's response
RESPONSE=$(echo "$INPUT" | jq -r '.assistant_response // .tool_result.content // ""' 2>/dev/null)

# If we can't read the response, clear pending and move on
if [ -z "$RESPONSE" ]; then
  jq '.nudge_pending = false' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  exit 0
fi

# Determine detection region based on escalation level
if [ "$NUDGE_IGNORED" -ge 1 ]; then
  # Level 2 (prefix): check first 200 chars
  CHECK_REGION=$(echo "$RESPONSE" | head -c 200)
else
  # Level 1 (suffix): check last 500 chars
  CHECK_REGION=$(echo "$RESPONSE" | tail -c 500)
fi

# Check for evidence that the nudge was delivered
DELIVERED=false

case "$NUDGE_TIER" in
  micro)
    if echo "$CHECK_REGION" | grep -qiE 'eyes off screen|look.*(away|across|far)|20 seconds|eye.?break'; then
      DELIVERED=true
    fi
    ;;
  suggest)
    if echo "$CHECK_REGION" | grep -qiE 'breather:stretch|minutes (in|since)|quick one'; then
      DELIVERED=true
    fi
    ;;
  insistent)
    if echo "$CHECK_REGION" | grep -qiE 'breather:pause|save.*(context|spot)|code will be here|step away|without a break'; then
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
  # Nudge delivered. Reset escalation.
  jq '.nudge_pending = false | .nudge_tier = null | .nudge_ignored_count = 0' \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
else
  # Nudge not delivered. Escalate.
  NEW_IGNORED=$((NUDGE_IGNORED + 1))
  jq ".nudge_pending = false | .nudge_tier = null | .nudge_ignored_count = $NEW_IGNORED" \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
fi

exit 0
