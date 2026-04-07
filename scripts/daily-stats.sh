#!/bin/bash
# Output daily stats as JSON. Called by skills that need global session data.
# Usage: bash ${CLAUDE_PLUGIN_ROOT}/scripts/daily-stats.sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/breather-lib.sh"

breather_read_all_sessions
