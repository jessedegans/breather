#!/bin/bash
# Shared library for breather scripts. Source this, don't execute it.
# Usage: source "$(dirname "$0")/breather-lib.sh"
#
# All functions are prefixed with breather_ to avoid collisions.
# No side effects on source -- only function definitions.

# --- Path helpers ---

breather_state_dir() {
  local dir="${CLAUDE_PLUGIN_DATA:-${HOME}/.local/share/breather}"
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

# Get the session file path for a given session ID.
# Falls back to "unknown" if no ID provided.
breather_session_file() {
  local sid="${1:-${BREATHER_SESSION_ID:-unknown}}"
  echo "$(breather_sessions_dir)/${sid}.json"
}

# --- Session management ---

# Create a session file if it doesn't exist (self-healing bootstrap).
# Args: $1 = session_id (optional, defaults to BREATHER_SESSION_ID)
breather_ensure_session() {
  local sid="${1:-${BREATHER_SESSION_ID:-unknown}}"
  local sf
  sf="$(breather_session_file "$sid")"

  if [ ! -f "$sf" ]; then
    local now
    now=$(date +%s)
    jq -n --arg sid "$sid" --argjson ts "$now" '{
      session_id: $sid,
      start_ts: $ts,
      prompt_count: 0,
      last_prompt_ts: $ts,
      full_breaks: 0,
      quick_breaks: 0,
      last_break_ts: $ts,
      last_full_break_ts: null,
      last_quick_break_ts: null,
      last_nudge_ts: 0,
      nudge_pending: false,
      nudge_tier: null,
      nudge_ignored_count: 0,
      break_committed_at: null,
      break_committed_min: null,
      intention: null,
      pattern_warning: ""
    }' > "$sf"
  fi

  echo "$sf"
}

# --- Staleness detection ---

# Returns 0 (true) if timestamp is 8+ hours ago (overnight = reset).
# Args: $1 = unix timestamp
breather_is_stale() {
  local ts="${1:-0}"
  local now
  now=$(date +%s)
  local diff=$((now - ts))
  local threshold=28800  # 8 hours in seconds
  [ "$diff" -ge "$threshold" ]
}

# --- Global aggregation ---

# Read all active session files and output aggregated JSON.
# Output: { today_total_min, since_last_break_min, total_breaks, total_prompts,
#           active_sessions, last_prompt_ts, any_nudge_ignored, max_nudge_ignored,
#           break_committed_at, break_committed_min }
breather_read_all_sessions() {
  local sessions_dir
  sessions_dir="$(breather_sessions_dir)"
  local history_file
  history_file="$(breather_history_file)"
  local now
  now=$(date +%s)
  local stale_threshold=28800  # 8 hours

  # Collect all session files (active)
  local files=()
  if compgen -G "$sessions_dir/*.json" > /dev/null 2>&1; then
    files=("$sessions_dir"/*.json)
  fi

  # If no active sessions, return zeroed output
  if [ ${#files[@]} -eq 0 ]; then
    jq -n '{
      today_total_min: 0,
      since_last_break_min: 0,
      total_breaks: 0,
      total_prompts: 0,
      active_sessions: 0,
      last_prompt_ts: 0,
      any_nudge_ignored: false,
      max_nudge_ignored: 0,
      break_committed_at: null,
      break_committed_min: null
    }'
    return
  fi

  # Merge all session files into one array, then aggregate
  local merged
  merged=$(jq -s '.' "${files[@]}" 2>/dev/null || echo '[]')

  # Find the most recent break timestamp across all sessions
  local last_break_ts
  last_break_ts=$(echo "$merged" | jq '[.[].last_break_ts // 0] | max')

  # Find the most recent prompt timestamp across all sessions
  local last_prompt_ts
  last_prompt_ts=$(echo "$merged" | jq '[.[].last_prompt_ts // 0] | max')

  # Check for overnight reset based on PROMPT ACTIVITY, not break age.
  # If the last prompt across all sessions was 8+ hours ago, this is a new day.
  # But if prompts are recent, the session is active regardless of how old
  # last_break_ts is. A 9-hour marathon should still show 9h since last break.
  local since_last_prompt_sec=$((now - last_prompt_ts))
  local since_last_break_sec=$((now - last_break_ts))
  local since_last_break_min

  if [ "$since_last_prompt_sec" -ge "$stale_threshold" ]; then
    # No prompts for 8+ hours. Fresh start.
    since_last_break_min=0
  else
    since_last_break_min=$((since_last_break_sec / 60))
  fi

  # Calculate "today" total: sum of session durations since last 8h+ gap
  # For simplicity, sum (now - start_ts) for all active sessions that started
  # after the last 8h gap. Also include recent history entries.
  local today_total_sec=0

  # Active sessions
  for f in "${files[@]}"; do
    local start_ts
    start_ts=$(jq -r '.start_ts // 0' "$f" 2>/dev/null)
    if ! breather_is_stale "$start_ts"; then
      today_total_sec=$((today_total_sec + now - start_ts))
    fi
  done

  # Recent history entries (sessions that ended today)
  if [ -f "$history_file" ]; then
    local history_today
    history_today=$(jq -s --argjson cutoff "$((now - stale_threshold))" \
      '[.[] | select(.end_ts > $cutoff)] | map(.duration_min // 0) | add // 0' \
      "$history_file" 2>/dev/null || echo 0)
    today_total_sec=$((today_total_sec + history_today * 60))
  fi

  local today_total_min=$((today_total_sec / 60))

  # Aggregate breaks and prompts (only from today's sessions)
  # Filter: only sessions where last_prompt_ts is within the stale threshold
  local cutoff=$((now - stale_threshold))
  local total_breaks
  total_breaks=$(echo "$merged" | jq --argjson cutoff "$cutoff" \
    '[.[] | select((.last_prompt_ts // 0) > $cutoff) | ((.full_breaks // 0) + (.quick_breaks // 0))] | add // 0')
  local total_prompts
  total_prompts=$(echo "$merged" | jq --argjson cutoff "$cutoff" \
    '[.[] | select((.last_prompt_ts // 0) > $cutoff) | .prompt_count // 0] | add // 0')

  # Nudge ignored status
  local max_nudge_ignored
  max_nudge_ignored=$(echo "$merged" | jq '[.[].nudge_ignored_count // 0] | max // 0')
  local any_nudge_ignored="false"
  if [ "$max_nudge_ignored" -ge 2 ]; then
    any_nudge_ignored="true"
  fi

  # Break commitment (from any session)
  local break_committed_at
  break_committed_at=$(echo "$merged" | jq '[.[].break_committed_at // null | select(. != null)] | max // null')
  local break_committed_min
  break_committed_min=$(echo "$merged" | jq '[.[].break_committed_min // null | select(. != null)] | first // null')

  jq -n \
    --argjson ttm "$today_total_min" \
    --argjson slbm "$since_last_break_min" \
    --argjson tb "$total_breaks" \
    --argjson tp "$total_prompts" \
    --argjson as "${#files[@]}" \
    --argjson lpt "$last_prompt_ts" \
    --argjson ani "$any_nudge_ignored" \
    --argjson mni "$max_nudge_ignored" \
    --argjson bca "$break_committed_at" \
    --argjson bcm "$break_committed_min" \
    '{
      today_total_min: $ttm,
      since_last_break_min: $slbm,
      total_breaks: $tb,
      total_prompts: $tp,
      active_sessions: $as,
      last_prompt_ts: $lpt,
      any_nudge_ignored: $ani,
      max_nudge_ignored: $mni,
      break_committed_at: $bca,
      break_committed_min: $bcm
    }'
}

# --- Migration ---

# Migrate v1 current-session.json to v2 sessions/ directory
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

    # Also migrate old history.jsonl -> history.jsonl (rename if needed)
    local old_history="$state_dir/session-history.jsonl"
    if [ -f "$old_history" ] && [ ! -f "$history_file" ]; then
      mv "$old_history" "$history_file"
    fi

    # Move session file
    mv "$old_file" "$sessions_dir/${sid}.json"
  fi
}
