---
name: pause
description: Use when the user wants to take a full break, step away, save their context, or says "pause", "break", "stepping away", "I need to stop". Also use when breather check-ins suggest a break and the user agrees. Supports "break in X mins" for deferred breaks. For quick breaks ("brb", "grabbing coffee", "need a sec"), use /breather:stretch instead.
argument-hint: optional reason or "in X mins" for deferred break
allowed-tools: Read, Write, Bash
---

# Pause - Save Context and Take a Break

The user is taking a break. Your job: make resuming effortless so the break feels free, not costly.

## Steps

1. **Check for deferred break** -- if the user said something like "break in 10 mins" or "pause in 15", extract the number of minutes and write the commitment to the session file:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/breather-lib.sh"
   NOW=$(date +%s)
   SF="$(breather_sessions_dir)/$(ls "$(breather_sessions_dir)" | head -1)"
   jq ".break_committed_at = $NOW | .break_committed_min = <MINUTES>" "$SF" > "${SF}.tmp" && mv "${SF}.tmp" "$SF"
   ```
   Then respond: "Got it, I'll remind you in [X] minutes." and continue normally.
   Do NOT proceed with the full pause flow below -- the break is deferred.

2. **Record the break** (only for immediate breaks) by running:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/record-break.sh
   ```

3. **Save a context snapshot** to `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md` containing:
   - What the user was working on (1-2 sentences)
   - Where they left off (specific file, function, or decision point)
   - What the logical next step is
   - Any open questions or blockers

4. **Read daily stats** by running:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/breather-lib.sh" && breather_read_all_sessions
   ```
   Use `today_total_min` for break duration suggestion.

5. **Suggest a break duration** based on daily total:
   - Under 50 min today: "5-10 minutes should do it"
   - 50-90 min today: "15-20 minutes - get outside if you can"
   - Over 90 min today: "Take a real break - 30 minutes minimum. Walk, eat, look at something that isn't a screen."

6. **Respond briefly.** No lectures. Something like:

   > Saved your context. You were [doing X], left off at [Y], next up is [Z].
   >
   > You've been going for [daily total] today. [Break suggestion].
   >
   > When you're back, just say "back" or /breather:back and I'll get you up to speed.
   > For a quick break without context saving, use /breather:stretch instead.

Keep it warm but short. They're taking a break - don't make them read a wall of text first.
