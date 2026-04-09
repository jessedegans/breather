#!/bin/bash
# Shared library for breather scripts. Source this, don't execute it.
# Usage: source "$(dirname "$0")/breather-lib.sh"
#
# All functions are prefixed with breather_ to avoid collisions.
# No side effects on source -- only function definitions.
#
# Architecture: single state.json for global state (fatigue, counters, nudge).
# Thin session pointer files in sessions/ for session identity only.

# --- Path helpers ---

breather_state_dir() {
  local dir=""

  # 1. Use CLAUDE_PLUGIN_DATA if set (hooks context)
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    dir="$CLAUDE_PLUGIN_DATA"
  else
    # 2. Auto-detect: look for the plugin data dir Claude Code creates
    local pattern="$HOME/.claude/plugins/data/breather-*"
    local found
    found=$(compgen -G "$pattern" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ -d "$found" ]; then
      dir="$found"
    else
      # 3. Fallback for manual testing / no plugin install
      dir="${HOME}/.local/share/breather"
    fi
  fi

  mkdir -p "$dir"
  echo "$dir"
}

breather_sessions_dir() {
  local dir="$(breather_state_dir)/sessions"
  mkdir -p "$dir"
  echo "$dir"
}

breather_history_file() {
  echo "$(breather_state_dir)/history.jsonl"
}

breather_state_file() {
  echo "$(breather_state_dir)/state.json"
}

# Get the session pointer file path for a given session ID.
breather_session_file() {
  local sid="${1:-${BREATHER_SESSION_ID:-unknown}}"
  echo "$(breather_sessions_dir)/${sid}.json"
}

# --- Staleness detection ---

# Returns 0 (true) if timestamp is 8+ hours ago (overnight = reset).
breather_is_stale() {
  local ts="${1:-0}"
  local now
  now=$(date +%s)
  local diff=$((now - ts))
  local threshold=28800  # 8 hours in seconds
  [ "$diff" -ge "$threshold" ]
}

# --- State file: read/write with flock ---

# Read state.json. No lock needed (atomic mv means reads always see complete JSON).
# Returns {} if missing.
breather_read_state() {
  local sf
  sf="$(breather_state_file)"
  if [ -f "$sf" ]; then
    cat "$sf"
  else
    echo '{}'
  fi
}

# Locked read-modify-write of state.json.
# Args: jq arguments and expression (passed directly to jq)
# Usage: breather_update_state '.counters.prompt_count += 1'
#        breather_update_state --argjson now "$NOW" '.fatigue.last_prompt_ts = $now'
# Outputs the updated JSON to stdout.
breather_update_state() {
  local sf
  sf="$(breather_state_file)"
  local lockfile="${sf}.lock"

  (
    flock -w 2 200 || { cat "$sf" 2>/dev/null || echo '{}'; return 1; }
    local current
    current=$(cat "$sf" 2>/dev/null || echo '{}')
    local updated
    updated=$(echo "$current" | jq "$@")
    echo "$updated" > "$sf"
    echo "$updated"
  ) 200>"$lockfile"
}

# --- Day reset ---

# Check if the calendar day has changed. If so, archive yesterday and reset counters.
# Call at start of session-start.sh and check-duration.sh.
breather_check_day_reset() {
  local sf
  sf="$(breather_state_file)"
  [ -f "$sf" ] || return 0

  local today
  today=$(date +%Y-%m-%d)
  local day_key
  day_key=$(jq -r '.day_key // ""' "$sf")

  if [ "$today" != "$day_key" ] && [ -n "$day_key" ]; then
    local history_file
    history_file="$(breather_history_file)"

    # Archive day summary to history
    jq -c '{
      type: "day_summary",
      day_key: .day_key,
      counters: .counters,
      sessions: (.sessions | keys | length),
      date: now | todate
    }' "$sf" >> "$history_file" 2>/dev/null || true

    # Reset counters, update day_key, keep fatigue and sessions
    local now
    now=$(date +%s)
    breather_update_state --argjson now "$now" --arg today "$today" '
      .day_key = $today |
      .counters.full_breaks = 0 |
      .counters.quick_breaks = 0 |
      .counters.prompt_count = 0 |
      .counters.today_active_sec = 0 |
      .fatigue.earliest_active_ts = $now
    ' > /dev/null
  fi
}

# --- JSON helpers ---

# Atomic multi-field update of a JSON file.
# Args: $1 = file path, remaining args = "field=value" or "+field" (increment)
# Usage: breather_set_many "$file" "last_break_ts=$NOW" "+full_breaks" "nudge_tier=null"
breather_set_many() {
  local file="$1"; shift
  [ -f "$file" ] || return 1

  local expr="."
  local -a jq_args=()
  local i=0

  for pair in "$@"; do
    # +field means increment by 1
    if [[ "$pair" == +* ]]; then
      local field="${pair#+}"
      expr="${expr} | .${field} = ((.${field} // 0) + 1)"
      continue
    fi

    local field="${pair%%=*}"
    local value="${pair#*=}"
    local var="v${i}"

    if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]] || [[ "$value" == "null" || "$value" == "true" || "$value" == "false" ]]; then
      jq_args+=(--argjson "$var" "$value")
    else
      jq_args+=(--arg "$var" "$value")
    fi

    expr="${expr} | .${field} = \$${var}"
    ((i++))
  done

  if jq "${jq_args[@]}" "$expr" "$file" > "${file}.tmp"; then
    mv "${file}.tmp" "$file"
  else
    rm -f "${file}.tmp"
    return 1
  fi
}

# --- State initialization ---

# Create state.json if it doesn't exist. Called by migration or first session-start.
breather_init_state() {
  local sf
  sf="$(breather_state_file)"
  [ -f "$sf" ] && return 0

  local now
  now=$(date +%s)
  local today
  today=$(date +%Y-%m-%d)

  jq -n --argjson now "$now" --arg today "$today" '{
    version: 3,
    day_key: $today,
    fatigue: {
      last_break_ts: 0,
      last_full_break_ts: null,
      last_quick_break_ts: null,
      last_prompt_ts: $now,
      earliest_active_ts: $now
    },
    counters: {
      full_breaks: 0,
      quick_breaks: 0,
      prompt_count: 0,
      today_active_sec: 0
    },
    nudge: {
      last_nudge_ts: 0,
      pending: false,
      pending_session_id: null,
      tier: null,
      ignored_count: 0
    },
    commitment: {
      break_committed_at: null,
      break_committed_min: null
    },
    sessions: {}
  }' > "$sf"
}

# --- Computed fields (read from state.json) ---

# Calculate since_last_break_min from state.json.
# Handles: no break taken (fall back to earliest_active_ts), overnight reset.
breather_since_last_break_min() {
  local state="$1"
  local now
  now=$(date +%s)

  local last_break_ts last_prompt_ts earliest_active_ts
  last_break_ts=$(echo "$state" | jq -r '.fatigue.last_break_ts // 0')
  last_prompt_ts=$(echo "$state" | jq -r '.fatigue.last_prompt_ts // 0')
  earliest_active_ts=$(echo "$state" | jq -r '.fatigue.earliest_active_ts // 0')

  local since_last_prompt_sec=$((now - last_prompt_ts))

  if [ "$since_last_prompt_sec" -ge 28800 ]; then
    # No prompts for 8+ hours. Fresh start.
    echo 0
  elif [ "$last_break_ts" -le 0 ] 2>/dev/null; then
    # No break ever taken. Measure from earliest active session.
    if [ "$earliest_active_ts" -gt 0 ] 2>/dev/null; then
      echo $(( (now - earliest_active_ts) / 60 ))
    else
      echo 0
    fi
  else
    echo $(( (now - last_break_ts) / 60 ))
  fi
}

# Calculate today_total_min from state.json.
# Uses today_active_sec (incremental counter) with wall-clock fallback.
breather_today_total_min() {
  local state="$1"
  local now
  now=$(date +%s)

  local today_active_sec earliest_active_ts
  today_active_sec=$(echo "$state" | jq -r '.counters.today_active_sec // 0')
  earliest_active_ts=$(echo "$state" | jq -r '.fatigue.earliest_active_ts // 0')

  local incremental_min=0
  local wallclock_min=0

  if [ "$today_active_sec" -gt 0 ]; then
    incremental_min=$(( today_active_sec / 60 ))
  fi

  if [ "$earliest_active_ts" -gt 0 ] 2>/dev/null; then
    wallclock_min=$(( (now - earliest_active_ts) / 60 ))
  fi

  # Use whichever is larger. Wall-clock serves as a floor during the
  # transition period after migration (when today_active_sec starts at 0).
  # Once the counter catches up over a full day, it'll naturally be larger.
  if [ "$incremental_min" -gt "$wallclock_min" ]; then
    echo "$incremental_min"
  else
    echo "$wallclock_min"
  fi
}

# --- Migration ---

# Migrate v2 (per-session with counters) to v3 (single state.json).
# Idempotent: skips if state.json already exists.
breather_migrate_v2_to_v3() {
  local state_dir
  state_dir="$(breather_state_dir)"
  local sf="$state_dir/state.json"
  local sessions_dir="$state_dir/sessions"

  # Already migrated?
  [ -f "$sf" ] && return 0

  # No sessions dir = nothing to migrate, just init fresh
  if [ ! -d "$sessions_dir" ] || ! compgen -G "$sessions_dir/*.json" > /dev/null 2>&1; then
    breather_init_state
    return 0
  fi

  local now
  now=$(date +%s)
  local today
  today=$(date +%Y-%m-%d)
  local stale_threshold=28800

  # Collect data from existing v2 session files
  local max_full=0 max_quick=0 total_prompts=0
  local max_last_prompt=0 max_last_break=0 earliest_start=$now
  local max_nudge_ignored=0 last_nudge_ts=0
  local nudge_pending="false" nudge_tier="null" nudge_pending_sid="null"
  local break_committed_at="null" break_committed_min="null"
  local sessions_map="{}"

  for f in "$sessions_dir"/*.json; do
    local sid start_ts last_prompt prompt_count full quick last_break
    local n_ignored n_nudge_ts n_pending n_tier
    local bca bcm

    sid=$(jq -r '.session_id // "unknown"' "$f")
    start_ts=$(jq -r '.start_ts // 0' "$f")
    last_prompt=$(jq -r '.last_prompt_ts // 0' "$f")
    prompt_count=$(jq -r '.prompt_count // 0' "$f")
    full=$(jq -r '.full_breaks // 0' "$f")
    quick=$(jq -r '.quick_breaks // 0' "$f")
    last_break=$(jq -r '.last_break_ts // 0' "$f")
    n_ignored=$(jq -r '.nudge_ignored_count // 0' "$f")
    n_nudge_ts=$(jq -r '.last_nudge_ts // 0' "$f")
    n_pending=$(jq -r '.nudge_pending // false' "$f")
    n_tier=$(jq -r '.nudge_tier // null' "$f")
    bca=$(jq -r '.break_committed_at // null' "$f")
    bcm=$(jq -r '.break_committed_min // null' "$f")

    # Skip stale sessions (archive them)
    if [ $((now - last_prompt)) -ge "$stale_threshold" ]; then
      local elapsed=$(( (last_prompt - start_ts) / 60 ))
      if [ "$elapsed" -gt 1 ]; then
        local history_file
        history_file="$(breather_history_file)"
        jq -c ". + {end_ts: $last_prompt, duration_min: $elapsed, date: \"$(date -Iseconds)\"}" "$f" >> "$history_file"
      fi
      rm -f "$f"
      continue
    fi

    # Use max for break counts (v2 duplicated them across sessions)
    [ "$full" -gt "$max_full" ] && max_full=$full
    [ "$quick" -gt "$max_quick" ] && max_quick=$quick
    total_prompts=$((total_prompts + prompt_count))
    [ "$last_prompt" -gt "$max_last_prompt" ] && max_last_prompt=$last_prompt
    [ "$last_break" -gt "$max_last_break" ] && max_last_break=$last_break
    [ "$start_ts" -lt "$earliest_start" ] && earliest_start=$start_ts
    [ "$n_ignored" -gt "$max_nudge_ignored" ] && max_nudge_ignored=$n_ignored
    [ "$n_nudge_ts" -gt "$last_nudge_ts" ] && last_nudge_ts=$n_nudge_ts

    if [ "$n_pending" = "true" ]; then
      nudge_pending="true"
      nudge_tier="\"$n_tier\""
      nudge_pending_sid="\"$sid\""
    fi

    if [ "$bca" != "null" ]; then
      break_committed_at=$bca
      break_committed_min=$bcm
    fi

    # Add to sessions map
    sessions_map=$(echo "$sessions_map" | jq \
      --arg sid "$sid" \
      --argjson start "$start_ts" \
      --argjson lp "$last_prompt" \
      '. + {($sid): {start_ts: $start, last_prompt_ts: $lp}}')

    # Slim down session file to pointer format
    jq '{session_id, start_ts, last_prompt_ts, prompt_count}' "$f" > "${f}.tmp" \
      && mv "${f}.tmp" "$f"
  done

  # Create state.json
  jq -n \
    --argjson v 3 \
    --arg dk "$today" \
    --argjson lb "$max_last_break" \
    --argjson lfb "null" \
    --argjson lqb "null" \
    --argjson lp "$max_last_prompt" \
    --argjson ea "$earliest_start" \
    --argjson fb "$max_full" \
    --argjson qb "$max_quick" \
    --argjson pc "$total_prompts" \
    --argjson lnt "$last_nudge_ts" \
    --argjson np "$nudge_pending" \
    --argjson nps "$nudge_pending_sid" \
    --argjson nt "$nudge_tier" \
    --argjson nic "$max_nudge_ignored" \
    --argjson bca "$break_committed_at" \
    --argjson bcm "$break_committed_min" \
    --argjson sm "$sessions_map" \
    '{
      version: $v,
      day_key: $dk,
      fatigue: {
        last_break_ts: $lb,
        last_full_break_ts: $lfb,
        last_quick_break_ts: $lqb,
        last_prompt_ts: $lp,
        earliest_active_ts: $ea
      },
      counters: {
        full_breaks: $fb,
        quick_breaks: $qb,
        prompt_count: $pc,
        today_active_sec: 0
      },
      nudge: {
        last_nudge_ts: $lnt,
        pending: $np,
        pending_session_id: $nps,
        tier: $nt,
        ignored_count: $nic
      },
      commitment: {
        break_committed_at: $bca,
        break_committed_min: $bcm
      },
      sessions: $sm
    }' > "$sf"
}

# Migrate v1 current-session.json to v2 sessions/ directory (kept for compat)
breather_migrate_v1() {
  local state_dir
  state_dir="$(breather_state_dir)"
  local old_file="$state_dir/current-session.json"
  local history_file
  history_file="$(breather_history_file)"

  if [ -f "$old_file" ]; then
    local sid
    sid=$(jq -r '.session_id // "migrated"' "$old_file")
    local sessions_dir
    sessions_dir="$(breather_sessions_dir)"

    local old_history="$state_dir/session-history.jsonl"
    if [ -f "$old_history" ] && [ ! -f "$history_file" ]; then
      mv "$old_history" "$history_file"
    fi

    mv "$old_file" "$sessions_dir/${sid}.json"
  fi
}
