# Breather Launch Spec

**Goal:** Ship breather as a public Claude Code plugin that actually works.
**Status:** v0.1.0, core features working, not yet public.

---

## The one thing that matters

The nudge bypass problem. Claude can rationalize skipping wellness nudges because they route through the LLM as prompt instructions. If Claude ignores them, the plugin doesn't work. Everything else is polish.

### Fix: Stop hook enforcement

Add a Stop hook that fires after every Claude response. The hook:
1. Reads `current-session.json` to check if a nudge was due (based on thresholds + last_nudge_ts)
2. Scans Claude's response for evidence of the nudge being delivered
3. If nudge was due but missing, injects a follow-up: "By the way - you've been at this for [X] minutes. /breather:pause saves your spot."

This bypasses Claude's judgment entirely for the critical path. Claude still gets the conversational nudge instruction (nice when it works), but the Stop hook is the safety net.

**Alternative (simpler, less reliable):** Beef up the prompt to "You MUST include a break suggestion as the FIRST LINE of your response." Won't always work but costs nothing to try first.

---

## Pre-launch checklist

In order. Don't skip ahead.

### 1. Nudge enforcement (the product risk)
- [ ] Try the stronger prompt approach first ("MUST", "FIRST LINE") -- cheap test
- [ ] If Claude still skips nudges, implement Stop hook enforcement
- [ ] Test: run a 60+ min session and verify nudges actually appear in responses

### 2. Validate
- [ ] Run `claude plugin validate` and fix whatever it flags
- [ ] Test fresh install: `claude plugin add` from marketplace repo
- [ ] Verify all 5 skills trigger correctly
- [ ] Verify statusline shows and updates
- [ ] Verify session-start.sh fires and creates state file

### 3. Version bump
- [ ] Bump plugin.json to 1.0.0
- [ ] Create CHANGELOG.md (just one entry: "1.0.0 - Initial release")

### 4. Demo GIF
- [ ] Record terminal session showing: session start -> work -> nudge appears -> /breather:pause -> context saved -> /breather:back -> context restored
- [ ] Keep it under 30 seconds
- [ ] Add to README

### 5. Ship it
- [ ] Push to GitHub as public repo (or make jessedegans-plugins public)
- [ ] Submit to Anthropic marketplace via clau.de/plugin-directory-submission
- [ ] Post on r/ClaudeAI -- personal angle: "AI was burning me out so I built this"
- [ ] Post on r/ClaudeCode -- technical angle: hooks architecture, statusline
- [ ] Tweet thread if you feel like it
- [ ] Don't stress about stars. If 10 people actually use it, that's a win.

---

## After launch

Only if there's traction. Don't build features nobody asked for.

- [ ] `/breather:history` -- view session patterns (people will ask for this)
- [ ] Configurable thresholds via plugin settings
- [ ] `/breather:weekly` -- weekly wellness report
- [ ] Cross-list on directories (skills.sh, awesome lists, etc.)
- [ ] DEV.to article if HN/Reddit gets traction

---

## What not to do

- Don't build team mode, OS notifications, calendar integration, or pomodoro mode before launch
- Don't optimize the GTM funnel before you know if people care
- Don't wait for the perfect README -- ship, then iterate
- Don't chase stars. Chase "I actually use this every day" feedback.
