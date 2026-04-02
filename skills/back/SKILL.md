---
name: back
description: Use when the user returns from a break and says "I'm back", "back", "where was I", "what was I doing", "resume work".
---

# Resume - Restore Context After a Break

The user is back from a break. Your job: get them oriented fast so they don't have to mentally reload.

## Steps

1. **Read the context snapshot** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md`. If the file doesn't exist, skip to step 3 and instead say: "No saved context from a previous pause. What are you picking up today?"

2. **Read daily stats** by running:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/breather-lib.sh" && breather_read_all_sessions
   ```

3. **Welcome them back in one natural paragraph.** Write it like you're talking to them, not filing a report. Reconstruct their mental state -- what was in their head when they stopped, what they were about to do next, and the one thing that matters most right now.

   Good example:
   > You were making the indexing pipeline crash-resilient. All 7 tasks are done, tests pass. Next up: run the end-to-end test (`make run-deps-semdex && make fetch && make index`), then write the ADR. The ADR is the last thing before this is merge-ready.

   Bad example (too structured, requires parsing):
   > **Working on:** BAC-977 Resilient Blue/Green Indexing Pipeline
   > **Left off at:** All 7 implementation tasks done on feature/bac-977
   > **Next step:** Test end-to-end, then ADR, then PR

   The good version reads like a colleague catching you up in 10 seconds. The bad version reads like a JIRA ticket.

   End with "Ready to pick up?" or similar.

4. **Archive the context snapshot** so calling /back twice doesn't show stale context:
   ```bash
   mv "${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md" "${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-context.md.used"
   ```

5. **Do NOT** ask how their break was, comment on how long they were gone, or add any preachy messaging. They're in work mode now. Respect that.
