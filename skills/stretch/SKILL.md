---
name: stretch
description: Use when the user wants a quick break, says "stretch", "quick break", "brb", "grabbing coffee", "need a sec", or agrees to a micro-break suggestion.
---

# Stretch - Quick Break

The user is taking a quick break. Not leaving, just stepping away from the screen briefly.

IMPORTANT: The user may walk away immediately. Use Read/Write tools, NOT Bash, so nothing blocks on permission prompts.

## Steps

1. **Record the quick break** by reading and updating ALL session files in `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/sessions/`. For each `.json` file:
   - Read the file
   - Increment `quick_breaks` by 1, set `last_quick_break_ts` to current timestamp, advance `last_break_ts` by 600 seconds (partial fatigue reset, +10 min)
   - Write back

2. **Respond in one line.** No context saving, no ceremony. Something like:

   > [X]h [Y]m in today. Good call. I'll be here.

3. **Do NOT** save context, suggest break duration, or add any preachy messaging. They said quick break, respect that.
