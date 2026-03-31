---
name: reflect
description: Use when the user is wrapping up a session and says "reflect", "done for today", "wrapping up", "end of day", "session summary", or "what did I do today".
allowed-tools: Read, Bash
---

# Reflect - End-of-Session Review

The user is wrapping up. Give them a clear picture of what happened and set up tomorrow.

## Steps

1. **Read session state** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/current-session.json`

2. **Read session history** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/session-history.jsonl` (if it exists) to provide weekly context.

3. **Review the conversation** to identify what was accomplished this session. For long sessions, also check project files, notes, or context snapshots in the working directory and `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/` to fill gaps.

4. **Provide a session summary:**

   > ## Session Recap
   >
   > **Duration:** [X]h [Y]m | **Prompts:** [N] | **Breaks:** [full_breaks] full + [quick_breaks] quick
   >
   > **What you did:**
   > - [Accomplishment 1]
   > - [Accomplishment 2]
   > - [Accomplishment 3]
   >
   > **Open threads:**
   > - [Unfinished thing 1]
   > - [Unfinished thing 2]
   >
   > **For next time:**
   > - [Suggested starting point]

5. **If session history exists**, add a weekly view:
   > **This week:** [N] sessions, [X]h total, avg [Y]h per session, [Z] breaks total.

6. **If the session was long with no breaks**, note it factually - not as a lecture, but as data. Thresholds: 50min = suggest break, 90min = insist, 120min = marathon. Read `full_breaks` and `quick_breaks` fields from the session state (not the old `breaks_taken` field).
   > Note: 4h straight, no breaks. That's been the pattern this week. Something to think about.

7. **Save the reflection** to `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-reflection.md` so the next session can reference it.

8. **End positively** - acknowledge what they shipped, not what they should have done differently.
