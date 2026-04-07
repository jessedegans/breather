---
name: stretch
description: Use when the user wants a quick break, says "stretch", "quick break", "brb", "grabbing coffee", "need a sec", or agrees to a micro-break suggestion.
---

# Stretch - Quick Break

The user is taking a quick break. Not leaving, just stepping away from the screen briefly.

## Steps

1. **Record the quick break FIRST** (before responding) by running:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/record-stretch.sh
   ```
   Do this before writing anything else. The user may walk away immediately.

2. **Respond in one line.** No context saving, no ceremony. Something like:

   > [X]h [Y]m in today. Good call. I'll be here.

3. **Do NOT** save context, suggest break duration, or add any preachy messaging. They said quick break, respect that.
