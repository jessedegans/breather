#!/bin/bash
# Called when user takes a full break.
# Single state.json update: increment counter, reset fatigue, clear commitment.
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

NOW=$(date +%s)

breather_update_state --argjson now "$NOW" '
  .counters.full_breaks += 1 |
  .fatigue.last_break_ts = $now |
  .fatigue.last_full_break_ts = $now |
  .nudge.ignored_count = 0 |
  .commitment.break_committed_at = null |
  .commitment.break_committed_min = null
' > /dev/null
