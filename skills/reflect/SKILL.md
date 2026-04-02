---
name: reflect
description: Use when the user is wrapping up a session and says "reflect", "done for today", "wrapping up", "end of day", "session summary", or "what did I do today".
allowed-tools: Read, Write, Bash
---

# Reflect - End-of-Session Review

The user is wrapping up. Give them a clear picture of what happened and set up tomorrow.

## Steps

1. **Read daily stats** by running:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/breather-lib.sh" && breather_read_all_sessions
   ```
   This gives you today_total_min, total_breaks, total_prompts, active_sessions.

2. **Read session history** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/history.jsonl` (if it exists) to provide weekly context.

3. **Review the conversation** to identify what was accomplished this session. For long sessions, also check project files, notes, or context snapshots in the working directory and `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/` to fill gaps.

4. **Provide a session summary:**

   > ## Session Recap
   >
   > **Today:** [X]h [Y]m across [N] sessions | **Prompts:** [N] | **Breaks:** [N]
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

6. **If today was long with few breaks**, note it factually - not as a lecture, but as data.
   > Note: 4h today, 1 break. Something to think about for tomorrow.

7. **Save the reflection** in two places:
   - `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/last-reflection.md` -- overwritten each time
   - **Append** to `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/reflections.md` -- running log of all reflections, separated by `---`. Prepend a `## YYYY-MM-DD HH:MM` header to each entry.

8. **End positively** - acknowledge what they shipped, not what they should have done differently.
