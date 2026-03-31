---
name: pause
description: Use when the user wants to take a full break, step away, save their context, or says "pause", "break", "stepping away", "I need to stop". Also use when breather check-ins suggest a break and the user agrees. For quick breaks ("brb", "grabbing coffee", "need a sec"), use /breather:stretch instead.
argument-hint: optional reason for pausing
allowed-tools: Read, Write, Bash
---

# Pause - Save Context and Take a Break

The user is taking a break. Your job: make resuming effortless so the break feels free, not costly.

## Steps

1. **Record the break** by running:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/record-break.sh
   ```

2. **Save a context snapshot** to `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md` containing:
   - What the user was working on (1-2 sentences)
   - Where they left off (specific file, function, or decision point)
   - What the logical next step is
   - Any open questions or blockers

3. **Read the session state** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/current-session.json` to get session duration and prompt count.

4. **Suggest a break duration** based on time since last break (or total session time if no breaks taken):
   - Under 50 min: "5-10 minutes should do it"
   - 50-90 min: "15-20 minutes - get outside if you can"
   - Over 90 min: "Take a real break - 30 minutes minimum. Walk, eat, look at something that isn't a screen."

5. **Respond briefly.** No lectures. Something like:

   > Saved your context. You were [doing X], left off at [Y], next up is [Z].
   >
   > You've been going for [duration]. [Break suggestion].
   >
   > When you're back, just say "back" or /breather:back and I'll get you up to speed.
   > For a quick break without context saving, use /breather:stretch instead.

Keep it warm but short. They're taking a break - don't make them read a wall of text first.
