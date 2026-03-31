---
name: back
description: Use when the user returns from a break and says "I'm back", "back", "where was I", "what was I doing", "resume work".
allowed-tools: Read, Bash
---

# Resume - Restore Context After a Break

The user is back from a break. Your job: get them oriented fast so they don't have to mentally reload.

## Steps

1. **Read the context snapshot** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md`. If the file doesn't exist, skip to step 3 and instead say: "No saved context from a previous pause. What are you picking up today?"

2. **Read session state** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/current-session.json` to check how the session is going.

3. **Welcome them back briefly:**

   > Welcome back. Here's where you left off:
   >
   > **Working on:** [what they were doing]
   > **Left off at:** [specific point]
   > **Next step:** [what to do next]
   >
   > [Any open questions from before the break]
   >
   > Ready to pick up?

Keep it scannable - bullet points or bold labels. They need to reload context, not read prose.

4. **Archive the context snapshot** so calling /back twice doesn't show stale context:
   ```bash
   mv "${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md" "${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md.used"
   ```

5. **Do NOT** ask how their break was, comment on how long they were gone, or add any wellness messaging. They're in work mode now. Respect that.
