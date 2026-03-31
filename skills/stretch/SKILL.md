---
name: stretch
description: Use when the user wants a quick break, says "stretch", "quick break", "brb", "grabbing coffee", "need a sec", or agrees to a micro-break suggestion.
allowed-tools: Read, Bash
---

# Stretch - Quick Break

The user is taking a quick break - not leaving, just stepping away from the screen briefly.

## Steps

1. **Record the quick break** by running:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/record-stretch.sh
   ```

2. **Read session state** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/current-session.json` to get session duration.

3. **Respond in one line.** No context saving, no ceremony. Something like:

   > [duration] in - good call. I'll be here.

   Or if they said what they're doing:

   > Go for it. [duration] in, stretch is earned.

4. **Do NOT** save context, suggest break duration, or add any wellness messaging. They said quick break, respect that.
