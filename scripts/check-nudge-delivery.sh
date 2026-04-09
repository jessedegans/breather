#!/bin/bash
# Stop hook -- checks if Claude actually delivered the break nudge.
# Position-aware detection:
#   Level 1 (suffix): check last 500 chars of response
#   Level 2 (prefix): check first 200 chars of response
#   Level 3 (bypass): no-op, statusline handles delivery
# If nudge wasn't delivered, increment nudge.ignored_count for escalation.
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

# Read session_id from stdin
INPUT=$(cat)
BREATHER_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
export BREATHER_SESSION_ID

STATE=$(breather_read_state)

# Check if a nudge was pending
NUDGE_PENDING=$(echo "$STATE" | jq -r '.nudge.pending // false')
[ "$NUDGE_PENDING" = "true" ] || exit 0

# Only check delivery in the session the nudge was sent to
NUDGE_SID=$(echo "$STATE" | jq -r '.nudge.pending_session_id // ""')
if [ -n "$NUDGE_SID" ] && [ "$NUDGE_SID" != "$BREATHER_SESSION_ID" ]; then
  exit 0
fi

NUDGE_TIER=$(echo "$STATE" | jq -r '.nudge.tier // ""')
NUDGE_IGNORED=$(echo "$STATE" | jq -r '.nudge.ignored_count // 0')

# Level 3 (bypass): statusline handles it. Clear pending, done.
if [ "$NUDGE_IGNORED" -ge 2 ] || [ "$NUDGE_TIER" = "bypass" ]; then
  breather_update_state '.nudge.pending = false' > /dev/null
  exit 0
fi

# Read Claude's response
RESPONSE=$(echo "$INPUT" | jq -r '.assistant_response // .tool_result.content // ""' 2>/dev/null)

# If we can't read the response, clear pending and move on
if [ -z "$RESPONSE" ]; then
  breather_update_state '.nudge.pending = false' > /dev/null
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
  breather_update_state '
    .nudge.pending = false |
    .nudge.tier = null |
    .nudge.pending_session_id = null |
    .nudge.ignored_count = 0
  ' > /dev/null
else
  # Nudge not delivered. Escalate.
  breather_update_state '
    .nudge.pending = false |
    .nudge.tier = null |
    .nudge.pending_session_id = null |
    .nudge.ignored_count += 1
  ' > /dev/null
fi

exit 0
