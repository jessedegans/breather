# Breather - Claude Code Plugin

Automatic break reminders for Claude Code. Tracks fatigue across all terminals, nudges Claude to suggest breaks, saves mental context so stopping is free.

## Current state

**Branch:** `v3/stabilize` (not merged to main)
**Version:** 0.2.0

### What works
- Hooks fire (SessionStart, UserPromptSubmit, Stop, SessionEnd)
- Session tracking in `sessions/{id}.json` via breather-lib.sh
- Global fatigue aggregation across multiple terminals
- All 5 skills (pause, stretch, back, checkin, reflect)
- Setup command (`/breather:setup`) configures statusline + auto-allow
- Nudge system (25/50/90 min thresholds)
- Nudge bypass detection (Stop hook checks if Claude delivered the nudge)
- Statusline: `breather 0h 45m · 3h 12m today · 1 break · 2 stretches`
- Break counter increments in current session only, fatigue reset in all
- Overnight reset (8h+ prompt gap = fresh day)

### Known issue: data path
Hooks use `CLAUDE_PLUGIN_DATA` (set by Claude Code to `~/.claude/plugins/data/breather-jessedegans-plugins/`). Skills and statusline fall back to `~/.local/share/breather/`. Fixed in breather-lib.sh with auto-detect: checks `CLAUDE_PLUGIN_DATA` first, then scans for the plugin data dir, then falls back.

### What's next (from brainstorm docs in docs/)
Four brainstorm specs were generated for the next iteration:

1. **`docs/brainstorm-single-state.md`** - Replace per-session files with one `state.json` + lightweight session pointers. Fixes double-counting complexity, simplifies aggregation from 100+ lines to one file read.

2. **`docs/brainstorm-helpers.md`** - `breather_get/set/inc/clear/update` helpers to replace raw jq one-liners. Makes scripts readable and testable.

3. **`docs/brainstorm-nudge-delivery.md`** - Suffix-first approach: let Claude answer fully, then append break reminder. Escalates: suffix -> prefix -> statusline bypass. ~99% estimated coverage.

4. **`docs/brainstorm-setup-ux.md`** - Kill the auto-allow question from setup. Everything except statusline works out of the box. Setup only adds the statusline config.

### Backlog
Full prioritized backlog at `docs/backlog.md`. Key items:
- P0s are all fixed on v3 branch
- P1: nudge framing (suffix approach), setup simplification
- P2: breather_get/set helpers, single state.json architecture, "last break: Xm ago" in statusline

### Spec
Design spec at `docs/superpowers/specs/2026-04-02-breather-v2-design.md`

### ADRs
Decision records at `docs/adr/`

## Architecture

```
hooks/hooks.json          - SessionStart, UserPromptSubmit, Stop, SessionEnd
scripts/
  breather-lib.sh         - Shared library (paths, sessions, aggregation, staleness)
  session-start.sh        - Creates session file, archives stale, marathon detection
  session-end.sh          - Archives to history.jsonl
  check-duration.sh       - Prompt counting, inactivity detection, nudge emission
  check-nudge-delivery.sh - Stop hook: did Claude deliver the nudge?
  record-break.sh         - Full break: counter in current session, fatigue reset in all
  record-stretch.sh       - Quick break: same pattern, partial reset (+10 min)
  statusline.sh           - Renders the status bar
  daily-stats.sh          - Wrapper for skills to read global stats
skills/
  pause/    - Full break with context save
  stretch/  - Quick break, one line
  back/     - Restore mental context (natural paragraph, not structured report)
  checkin/  - Session + daily stats
  reflect/  - End-of-day review, appends to reflections.md
commands/
  setup.md  - First-time setup (statusline config)
```

## Dev workflow

```bash
cd ~/projects/breather
# Edit files
./sync-cache.sh        # Syncs to Claude Code plugin cache
# Restart Claude Code to pick up changes
```

## Style rules
- No em-dashes in prose. Use periods, colons, or rephrase.
- No "wellness" language. Breather is a break reminder, not an HR initiative.
- No Co-Authored-By lines in commits.
