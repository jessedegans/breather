#!/bin/bash
# Called when user takes a quick stretch.
# Single state.json update: increment counter, partial fatigue reset (+10 min credit).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

NOW=$(date +%s)

# Partial reset: shift last_break_ts forward by 10 minutes, capped at now
breather_update_state --argjson now "$NOW" '
  .counters.quick_breaks += 1 |
  .fatigue.last_quick_break_ts = $now |
  .fatigue.last_break_ts = ([(.fatigue.last_break_ts + 600), $now] | min)
' > /dev/null
