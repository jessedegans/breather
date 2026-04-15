#!/usr/bin/env bash
# tests/test.sh -- Breather plugin test suite
#
# No external test frameworks. Standard Linux tooling: bash, jq, coreutils.
# Creates a temp directory as CLAUDE_PLUGIN_DATA for complete isolation.
#
# Usage: bash tests/test.sh
# Returns: 0 if all pass, non-zero if any fail.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TESTS_DIR")"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
LIB="$SCRIPTS_DIR/breather-lib.sh"

# --- Temp dir + cleanup ---

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export CLAUDE_PLUGIN_DATA="$TEST_DIR"

# --- Source the library ---

source "$LIB"

# --- Test harness ---

PASS_COUNT=0
FAIL_COUNT=0

group() {
  echo ""
  echo "=== $1 ==="
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  PASS  $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "  FAIL  $1"
  echo "        $2"
}

assert_eq() {
  local actual="$1" expected="$2" desc="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc" "expected='$expected' got='$actual'"
  fi
}

assert_ne() {
  local actual="$1" expected="$2" desc="$3"
  if [[ "$actual" != "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc" "expected not '$expected' but got that"
  fi
}

assert_ge() {
  local actual="$1" min="$2" desc="$3"
  if [ "$actual" -ge "$min" ] 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "expected >= $min, got $actual"
  fi
}

assert_le() {
  local actual="$1" max="$2" desc="$3"
  if [ "$actual" -le "$max" ] 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "expected <= $max, got $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc" "expected to contain '$needle'"
  fi
}

assert_file_exists() {
  local path="$1" desc="$2"
  if [ -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc" "file not found: $path"
  fi
}

assert_file_missing() {
  local path="$1" desc="$2"
  if [ ! -f "$path" ]; then
    pass "$desc"
  else
    fail "$desc" "file should not exist: $path"
  fi
}

STATE_FILE="$(breather_state_file)"
SESSIONS_DIR="$(breather_sessions_dir)"

reset_state() {
  rm -f "$STATE_FILE" "${STATE_FILE}.lock" "$TEST_DIR/history.jsonl"
  rm -rf "$SESSIONS_DIR"
  mkdir -p "$SESSIONS_DIR"
}

write_state() {
  local extra="${1:-.}"
  local now; now=$(date +%s)
  local today; today=$(date +%Y-%m-%d)
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
    counters: { full_breaks: 0, quick_breaks: 0, prompt_count: 0, today_active_sec: 0 },
    nudge: { last_nudge_ts: 0, pending: false, pending_session_id: null, tier: null, ignored_count: 0 },
    commitment: { break_committed_at: null, break_committed_min: null },
    sessions: {}
  }' | jq "$extra" > "$STATE_FILE"
}

# ===========================================================================
# Group 1: breather_is_stale
# ===========================================================================

group "breather_is_stale"

NOW=$(date +%s)

if breather_is_stale 0; then
  pass "is_stale: ts=0 is stale"
else
  fail "is_stale: ts=0 is stale" "returned false"
fi

if ! breather_is_stale "$NOW"; then
  pass "is_stale: current ts is not stale"
else
  fail "is_stale: current ts is not stale" "returned true"
fi

EIGHT_H_AGO=$((NOW - 28800))
if breather_is_stale "$EIGHT_H_AGO"; then
  pass "is_stale: exactly 8h ago is stale"
else
  fail "is_stale: exactly 8h ago is stale" "returned false"
fi

JUST_UNDER=$((NOW - 28799))
if ! breather_is_stale "$JUST_UNDER"; then
  pass "is_stale: 7h59m59s ago is not stale"
else
  fail "is_stale: 7h59m59s ago is not stale" "returned true"
fi

# ===========================================================================
# Group 2: breather_read_state + breather_update_state
# ===========================================================================

group "breather_read_state + breather_update_state"

reset_state

result=$(breather_read_state)
assert_eq "$result" "{}" "read_state: missing file returns {}"

breather_init_state
assert_file_exists "$STATE_FILE" "init_state: creates state.json"

ver=$(jq -r '.version' "$STATE_FILE")
assert_eq "$ver" "3" "init_state: version is 3"

today=$(date +%Y-%m-%d)
day_key=$(jq -r '.day_key' "$STATE_FILE")
assert_eq "$day_key" "$today" "init_state: day_key is today"

updated=$(breather_update_state '.counters.prompt_count = 7')
pc=$(echo "$updated" | jq -r '.counters.prompt_count')
assert_eq "$pc" "7" "update_state: sets field, returns updated JSON"

pc_on_disk=$(jq -r '.counters.prompt_count' "$STATE_FILE")
assert_eq "$pc_on_disk" "7" "update_state: persists to disk"

result=$(breather_update_state --argjson val 42 '.counters.full_breaks = $val')
fb=$(echo "$result" | jq -r '.counters.full_breaks')
assert_eq "$fb" "42" "update_state: --argjson arg passing works"

breather_update_state '.counters.prompt_count = 0' > /dev/null
for _ in 1 2 3; do
  breather_update_state '.counters.prompt_count += 1' > /dev/null
done
final=$(jq -r '.counters.prompt_count' "$STATE_FILE")
assert_eq "$final" "3" "update_state: += increments correctly"

# Flock concurrency test
breather_update_state '.counters.prompt_count = 0' > /dev/null
for _ in $(seq 1 5); do
  (
    source "$LIB"
    breather_update_state '.counters.prompt_count += 1' > /dev/null
  ) &
done
wait
concurrent_result=$(jq -r '.counters.prompt_count' "$STATE_FILE")
assert_eq "$concurrent_result" "5" "update_state: flock serializes concurrent increments"

# ===========================================================================
# Group 3: breather_set_many
# ===========================================================================

group "breather_set_many"

TMPJSON="$TEST_DIR/setmany_test.json"

echo '{"count":0,"label":"","active":false}' > "$TMPJSON"
breather_set_many "$TMPJSON" "count=99"
assert_eq "$(jq -r '.count' "$TMPJSON")" "99" "set_many: integer field=value"

breather_set_many "$TMPJSON" "label=hello"
assert_eq "$(jq -r '.label' "$TMPJSON")" "hello" "set_many: string field=value"

breather_set_many "$TMPJSON" "label=null"
assert_eq "$(jq -r '.label' "$TMPJSON")" "null" "set_many: null value"

breather_set_many "$TMPJSON" "active=true"
assert_eq "$(jq -r '.active' "$TMPJSON")" "true" "set_many: boolean true"

echo '{"count":0}' > "$TMPJSON"
breather_set_many "$TMPJSON" "+count"
assert_eq "$(jq -r '.count' "$TMPJSON")" "1" "set_many: +field increments from 0"

breather_set_many "$TMPJSON" "+count" "+count"
assert_eq "$(jq -r '.count' "$TMPJSON")" "3" "set_many: +field multiple in one call"

echo '{}' > "$TMPJSON"
breather_set_many "$TMPJSON" "+missing_field"
assert_eq "$(jq -r '.missing_field' "$TMPJSON")" "1" "set_many: +field on missing field"

echo '{"a":0,"b":""}' > "$TMPJSON"
breather_set_many "$TMPJSON" "a=1" "b=world"
assert_eq "$(jq -r '.a' "$TMPJSON")" "1" "set_many: multi-field a"
assert_eq "$(jq -r '.b' "$TMPJSON")" "world" "set_many: multi-field b"

echo '{"count":5,"label":"old"}' > "$TMPJSON"
breather_set_many "$TMPJSON" "+count" "label=new"
assert_eq "$(jq -r '.count' "$TMPJSON")" "6" "set_many: mixed +field and field=value"

# set -e safety: ((i++)) with i=0 must not kill the script
echo '{"x":0}' > "$TMPJSON"
set_e_result=$(
  set -e
  source "$LIB"
  export CLAUDE_PLUGIN_DATA="$TEST_DIR"
  breather_set_many "$TMPJSON" "x=42"
  echo "survived"
)
if echo "$set_e_result" | grep -q "survived"; then
  pass "set_many: survives set -e (no ((i++)) arithmetic kill)"
else
  fail "set_many: survives set -e" "((i++)) when i=0 exits 1 under set -e"
fi

if ! breather_set_many "$TEST_DIR/nonexistent.json" "a=1" 2>/dev/null; then
  pass "set_many: missing file returns non-zero"
else
  fail "set_many: missing file returns non-zero" "returned 0"
fi

rm -f "$TMPJSON"

# ===========================================================================
# Group 4: breather_since_last_break_min
# ===========================================================================

group "breather_since_last_break_min"

NOW=$(date +%s)

STATE=$(jq -n '{fatigue: {last_break_ts: 0, last_prompt_ts: '"$((NOW-10))"', earliest_active_ts: 0}}')
assert_eq "$(breather_since_last_break_min "$STATE")" "0" "since_break: no break, no earliest -> 0"

STATE=$(jq -n '{fatigue: {last_break_ts: 0, last_prompt_ts: '"$((NOW-10))"', earliest_active_ts: '"$((NOW-1800))"'}}')
assert_eq "$(breather_since_last_break_min "$STATE")" "30" "since_break: no break, earliest 30m ago -> 30"

STATE=$(jq -n '{fatigue: {last_break_ts: '"$((NOW-2700))"', last_prompt_ts: '"$((NOW-10))"', earliest_active_ts: '"$((NOW-5400))"'}}')
assert_eq "$(breather_since_last_break_min "$STATE")" "45" "since_break: break 45m ago -> 45"

STATE=$(jq -n '{fatigue: {last_break_ts: 0, last_prompt_ts: '"$((NOW-28800))"', earliest_active_ts: '"$((NOW-32400))"'}}')
assert_eq "$(breather_since_last_break_min "$STATE")" "0" "since_break: stale last_prompt (8h ago) -> 0"

# ===========================================================================
# Group 5: breather_today_total_min
# ===========================================================================

group "breather_today_total_min"

NOW=$(date +%s)

STATE=$(jq -n '{counters: {today_active_sec: 0}, fatigue: {earliest_active_ts: 0}}')
assert_eq "$(breather_today_total_min "$STATE")" "0" "today_total: both 0 -> 0"

STATE=$(jq -n '{counters: {today_active_sec: 7200}, fatigue: {earliest_active_ts: 0}}')
assert_eq "$(breather_today_total_min "$STATE")" "120" "today_total: only incremental -> 120"

STATE=$(jq -n '{counters: {today_active_sec: 0}, fatigue: {earliest_active_ts: '"$((NOW-3600))"'}}')
assert_eq "$(breather_today_total_min "$STATE")" "60" "today_total: only wallclock 60m -> 60"

STATE=$(jq -n '{counters: {today_active_sec: 600}, fatigue: {earliest_active_ts: '"$((NOW-5400))"'}}')
assert_eq "$(breather_today_total_min "$STATE")" "90" "today_total: wallclock (90) > incremental (10) -> 90"

# ===========================================================================
# Group 6: breather_check_day_reset
# ===========================================================================

group "breather_check_day_reset"

reset_state
write_state

TODAY=$(date +%Y-%m-%d)
jq --arg dk "$TODAY" '.day_key = $dk | .counters.full_breaks = 3' "$STATE_FILE" \
  > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
breather_check_day_reset
assert_eq "$(jq -r '.counters.full_breaks' "$STATE_FILE")" "3" "day_reset: today's date -> no reset"

jq '.day_key = "2020-01-01" | .counters.full_breaks = 3 | .counters.quick_breaks = 2' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
breather_check_day_reset
assert_eq "$(jq -r '.day_key' "$STATE_FILE")" "$TODAY" "day_reset: stale date -> day_key updated"
assert_eq "$(jq -r '.counters.full_breaks' "$STATE_FILE")" "0" "day_reset: full_breaks reset to 0"
assert_eq "$(jq -r '.counters.quick_breaks' "$STATE_FILE")" "0" "day_reset: quick_breaks reset to 0"

# ===========================================================================
# Group 7: breather_migrate_v2_to_v3
# ===========================================================================

group "breather_migrate_v2_to_v3"

reset_state

NOW=$(date +%s)
BREAK_TS=$((NOW - 1200))

# Session A: 2 breaks (active)
cat > "$SESSIONS_DIR/sess-a.json" <<EOF
{"session_id":"sess-a","start_ts":$((NOW-7200)),"last_prompt_ts":$((NOW-30)),"prompt_count":30,"full_breaks":2,"quick_breaks":1,"last_break_ts":$BREAK_TS,"nudge_ignored_count":0,"last_nudge_ts":0,"nudge_pending":false,"nudge_tier":null,"break_committed_at":null,"break_committed_min":null}
EOF

# Session B: same breaks (v2 duplication)
cat > "$SESSIONS_DIR/sess-b.json" <<EOF
{"session_id":"sess-b","start_ts":$((NOW-5400)),"last_prompt_ts":$((NOW-60)),"prompt_count":20,"full_breaks":2,"quick_breaks":0,"last_break_ts":$BREAK_TS,"nudge_ignored_count":0,"last_nudge_ts":0,"nudge_pending":false,"nudge_tier":null,"break_committed_at":null,"break_committed_min":null}
EOF

# Session C: stale
cat > "$SESSIONS_DIR/sess-c.json" <<EOF
{"session_id":"sess-c","start_ts":$((NOW-39600)),"last_prompt_ts":$((NOW-32400)),"prompt_count":10,"full_breaks":1,"quick_breaks":0,"last_break_ts":$((NOW-35000)),"nudge_ignored_count":0,"last_nudge_ts":0,"nudge_pending":false,"nudge_tier":null,"break_committed_at":null,"break_committed_min":null}
EOF

breather_migrate_v2_to_v3

assert_file_exists "$STATE_FILE" "migrate: state.json created"
assert_eq "$(jq -r '.counters.full_breaks' "$STATE_FILE")" "2" "migrate: full_breaks uses max() not sum()"
assert_eq "$(jq -r '.counters.quick_breaks' "$STATE_FILE")" "1" "migrate: quick_breaks uses max()"
assert_eq "$(jq -r '.counters.prompt_count' "$STATE_FILE")" "50" "migrate: prompt_count is sum of active"
assert_eq "$(jq -r '.sessions["sess-c"] // "null"' "$STATE_FILE")" "null" "migrate: stale session excluded"
assert_ne "$(jq -r '.sessions["sess-a"] // "null"' "$STATE_FILE")" "null" "migrate: active session A in map"
assert_file_missing "$SESSIONS_DIR/sess-c.json" "migrate: stale session file deleted"
assert_eq "$(jq 'keys | length' "$SESSIONS_DIR/sess-a.json")" "4" "migrate: session file slimmed to 4 fields"

# ===========================================================================
# Group 8: record-break.sh
# ===========================================================================

group "record-break.sh"

reset_state
write_state

NOW=$(date +%s)
jq --argjson now "$NOW" '.counters.full_breaks = 1 | .nudge.ignored_count = 3 | .commitment.break_committed_at = ($now - 600) | .commitment.break_committed_min = 10' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/record-break.sh"

assert_eq "$(jq -r '.counters.full_breaks' "$STATE_FILE")" "2" "record-break: full_breaks incremented"
assert_eq "$(jq -r '.nudge.ignored_count' "$STATE_FILE")" "0" "record-break: nudge.ignored_count reset"
assert_eq "$(jq -r '.commitment.break_committed_at' "$STATE_FILE")" "null" "record-break: commitment cleared"

# ===========================================================================
# Group 9: record-stretch.sh
# ===========================================================================

group "record-stretch.sh"

reset_state
write_state

NOW=$(date +%s)
jq --argjson ts "$((NOW-3600))" '.fatigue.last_break_ts = $ts | .fatigue.last_prompt_ts = '"$((NOW-10))"' | .fatigue.earliest_active_ts = '"$((NOW-3600))"'' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/record-stretch.sh"

assert_eq "$(jq -r '.counters.quick_breaks' "$STATE_FILE")" "1" "record-stretch: quick_breaks incremented"
last_break=$(jq -r '.fatigue.last_break_ts' "$STATE_FILE")
expected=$((NOW - 3000))
assert_ge "$last_break" "$((expected - 5))" "record-stretch: last_break_ts shifted +10min (lower)"
assert_le "$last_break" "$((expected + 5))" "record-stretch: last_break_ts shifted +10min (upper)"

# ===========================================================================
# Group 10: session-start.sh
# ===========================================================================

group "session-start.sh"

reset_state

SID="test-session-abc"
echo "{\"session_id\":\"$SID\"}" \
  | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/session-start.sh" > /dev/null 2>&1

assert_file_exists "$STATE_FILE" "session-start: creates state.json"
assert_file_exists "$SESSIONS_DIR/${SID}.json" "session-start: creates pointer file"
assert_ne "$(jq -r --arg s "$SID" '.sessions[$s].start_ts // "null"' "$STATE_FILE")" "null" "session-start: session in state.json"

# ===========================================================================
# Group 11: session-end.sh
# ===========================================================================

group "session-end.sh"

reset_state
write_state

SID2="end-session-xyz"
NOW=$(date +%s)

jq --arg sid "$SID2" --argjson start "$((NOW-300))" --argjson lp "$((NOW-10))" \
  '.sessions[$sid] = {start_ts: $start, last_prompt_ts: $lp}' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

jq -n --arg sid "$SID2" --argjson start "$((NOW-300))" --argjson lp "$((NOW-10))" \
  '{session_id: $sid, start_ts: $start, last_prompt_ts: $lp, prompt_count: 5}' \
  > "$SESSIONS_DIR/${SID2}.json"

echo "{\"session_id\":\"$SID2\"}" \
  | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/session-end.sh" > /dev/null 2>&1

assert_eq "$(jq -r --arg s "$SID2" '.sessions[$s] // "null"' "$STATE_FILE")" "null" "session-end: session removed from state"
assert_file_missing "$SESSIONS_DIR/${SID2}.json" "session-end: pointer file deleted"

# ===========================================================================
# Group 12: check-duration.sh nudge tiers
# ===========================================================================

group "check-duration.sh nudge tiers"

NOW=$(date +%s)
TODAY=$(date +%Y-%m-%d)
SID3="nudge-test-sid"

setup_nudge_state() {
  local min_ago="$1"
  local ea=$((NOW - min_ago * 60))
  reset_state
  jq -n --argjson now "$NOW" --argjson ea "$ea" --arg today "$TODAY" --arg sid "$SID3" '{
    version: 3, day_key: $today,
    fatigue: { last_break_ts: 0, last_full_break_ts: null, last_quick_break_ts: null,
      last_prompt_ts: ($now - 30), earliest_active_ts: $ea },
    counters: { full_breaks: 0, quick_breaks: 0, prompt_count: 5, today_active_sec: 0 },
    nudge: { last_nudge_ts: 0, pending: false, pending_session_id: null, tier: null, ignored_count: 0 },
    commitment: { break_committed_at: null, break_committed_min: null },
    sessions: { ($sid): { start_ts: $ea, last_prompt_ts: ($now - 30) } }
  }' > "$STATE_FILE"
  jq -n --arg sid "$SID3" --argjson ea "$ea" --argjson lp "$((NOW - 30))" \
    '{session_id: $sid, start_ts: $ea, last_prompt_ts: $lp, prompt_count: 5}' \
    > "$SESSIONS_DIR/${SID3}.json"
}

# Below threshold
setup_nudge_state 24
output=$(echo "{\"session_id\":\"$SID3\"}" | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-duration.sh" 2>/dev/null)
assert_eq "$output" "" "nudge: 24min -> no nudge"

# Micro tier
setup_nudge_state 25
output=$(echo "{\"session_id\":\"$SID3\"}" | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-duration.sh" 2>/dev/null)
assert_contains "$output" "Eyes off screen" "nudge: 25min -> micro tier"
assert_eq "$(jq -r '.nudge.tier' "$STATE_FILE")" "micro" "nudge: 25min -> tier=micro"

# Suggest tier
setup_nudge_state 50
output=$(echo "{\"session_id\":\"$SID3\"}" | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-duration.sh" 2>/dev/null)
assert_contains "$output" "since last break" "nudge: 50min -> suggest tier"

# Insistent tier
setup_nudge_state 90
output=$(echo "{\"session_id\":\"$SID3\"}" | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-duration.sh" 2>/dev/null)
assert_contains "$output" "without a break" "nudge: 90min -> insistent tier"

# Escalation: ignored=1 -> prefix
setup_nudge_state 90
jq '.nudge.ignored_count = 1' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
output=$(echo "{\"session_id\":\"$SID3\"}" | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-duration.sh" 2>/dev/null)
assert_contains "$output" "Start your response with" "nudge: ignored=1 -> prefix"

# Escalation: ignored=2 -> bypass
setup_nudge_state 90
jq '.nudge.ignored_count = 2' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
output=$(echo "{\"session_id\":\"$SID3\"}" | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-duration.sh" 2>/dev/null)
assert_contains "$output" "status bar" "nudge: ignored=2 -> bypass"

# Cooldown
setup_nudge_state 90
jq --argjson lnt "$((NOW - 540))" '.nudge.last_nudge_ts = $lnt' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
output=$(echo "{\"session_id\":\"$SID3\"}" | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-duration.sh" 2>/dev/null)
assert_eq "$output" "" "nudge: cooldown (9min ago) -> no nudge"

# ===========================================================================
# Group 13: check-nudge-delivery.sh
# ===========================================================================

group "check-nudge-delivery.sh"

reset_state
write_state

NOW=$(date +%s)
SID4="delivery-test-sid"

# Nudge delivered
jq --arg sid "$SID4" '.nudge.pending = true | .nudge.pending_session_id = $sid | .nudge.tier = "insistent" | .nudge.ignored_count = 0' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
echo "{\"session_id\":\"$SID4\",\"assistant_response\":\"/breather:pause saves your context. The code will be here when you get back.\"}" \
  | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-nudge-delivery.sh" > /dev/null 2>&1
assert_eq "$(jq -r '.nudge.pending' "$STATE_FILE")" "false" "delivery: delivered -> pending cleared"
assert_eq "$(jq -r '.nudge.ignored_count' "$STATE_FILE")" "0" "delivery: delivered -> ignored reset"

# Nudge not delivered
jq --arg sid "$SID4" '.nudge.pending = true | .nudge.pending_session_id = $sid | .nudge.tier = "insistent" | .nudge.ignored_count = 0' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
echo "{\"session_id\":\"$SID4\",\"assistant_response\":\"Here is the code you asked for.\"}" \
  | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-nudge-delivery.sh" > /dev/null 2>&1
assert_eq "$(jq -r '.nudge.ignored_count' "$STATE_FILE")" "1" "delivery: not delivered -> ignored incremented"

# Wrong session -> no change
jq --arg sid "other-sid" '.nudge.pending = true | .nudge.pending_session_id = $sid | .nudge.tier = "micro" | .nudge.ignored_count = 0' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
echo "{\"session_id\":\"$SID4\",\"assistant_response\":\"whatever\"}" \
  | env CLAUDE_PLUGIN_DATA="$TEST_DIR" bash "$SCRIPTS_DIR/check-nudge-delivery.sh" > /dev/null 2>&1
assert_eq "$(jq -r '.nudge.pending' "$STATE_FILE")" "true" "delivery: wrong session -> unchanged"

# ===========================================================================
# Summary
# ===========================================================================

echo ""
echo "================================================================"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "================================================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
else
  exit 0
fi
