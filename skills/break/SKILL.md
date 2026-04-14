---
name: break
description: Full break. Saves your mental context so you can stop without losing your place. Fully resets the fatigue clock.
when_to_use: User says "pause", "break", "take a break", "stepping away", "I need to stop". Also when breather nudges suggest a break and the user agrees. For quick breaks ("brb", "grabbing coffee"), use /breather:stretch instead.
argument-hint: optional reason or "in X mins" for deferred break
allowed-tools: Bash, Read, Write
---

# Pause - Save Context and Take a Break

The user is taking a break. Your job: make resuming effortless so the break feels free, not costly.

## Steps

1. **Check for deferred break.** If the user said "break in 10 mins" or similar, just acknowledge it: "Got it, I'll remind you in [X] minutes." Do NOT proceed with the full pause flow below.

2. **Record the break FIRST** (before responding) by running:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/record-break.sh
   ```
   Do this before writing anything else. The user may walk away after saying "pause."

3. **Save a context snapshot** to `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md`. Write it as a natural paragraph that reconstructs the user's mental state. Not a structured template. It should read like a colleague's note to themselves: what they were doing, the specific point they stopped at (file, function, command), what they were about to do next, and anything unresolved.

   Good example:
   > Working on the nudge delivery rewrite for breather. Finished rewriting check-duration.sh with the suffix/prefix/bypass escalation. check-nudge-delivery.sh now has position-aware detection. Statusline bypass state is done. All three files pass syntax check and are synced to the plugin cache. Next up: setup simplification (wrapper script, informed auto-allow). The brainstorm spec is in docs/brainstorm-setup-ux.md.

   Bad example (too structured, hard to mentally reload from):
   > **Task:** Nudge delivery rewrite
   > **Files changed:** check-duration.sh, check-nudge-delivery.sh, statusline.sh
   > **Status:** Complete
   > **Next:** Setup simplification

4. **Read daily stats** by running:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/daily-stats.sh"
   ```
   Use `today_total_min` for break duration suggestion.

5. **Suggest a break duration** based on daily total:
   - Under 50 min today: "5-10 minutes should do it"
   - 50-90 min today: "15-20 minutes. Get outside if you can."
   - Over 90 min today: "Take a real break. 30 minutes minimum. Walk, eat, look at something that isn't a screen."

6. **Respond briefly.** No lectures. Something like:

   > Saved your context. You were [doing X], left off at [Y], next up is [Z].
   >
   > You've been going for [daily total] today. [Break suggestion].
   >
   > When you're back, just say "back" or /breather:back.

Keep it warm but short. They're taking a break. Don't make them read a wall of text first.
