#!/bin/bash
# Called when user takes a full break. Updates ALL active sessions
# because a break is global (one human, one brain, many terminals).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

NOW=$(date +%s)

# A break resets fatigue everywhere. Update all non-stale sessions.
breather_update_all_sessions ".full_breaks = (.full_breaks // 0) + 1 | .last_break_ts = $NOW | .last_full_break_ts = $NOW | .break_committed_at = null | .break_committed_min = null | .nudge_ignored_count = 0"
