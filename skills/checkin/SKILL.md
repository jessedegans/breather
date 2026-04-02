---
name: checkin
description: Use when the user asks "how am I doing", "session status", "how long have I been working", "check in", "checkin", "am I overdue for a break", or wants to know their current session stats.
allowed-tools: Read, Bash
---

# Check In - Session Status

Provide an honest, non-preachy assessment of the current session AND daily totals.

## Steps

1. **Read this session's state** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/sessions/` (find this session's file by session_id, or read the most recent one).

2. **Read all session files** to compute daily totals. Run:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/breather-lib.sh" && breather_read_all_sessions
   ```
   This returns JSON with: today_total_min, since_last_break_min, total_breaks, total_prompts, active_sessions.

3. **Present both session and daily stats.** Tone depends on the daily numbers:

   **Under 50 min today, breaks taken:** Just the facts, positive.
   > This session: 22m, 12 prompts. Today: 42m total, 1 break. You're in good shape.

   **50-90 min today, no break:** Neutral observation.
   > This session: 35m, 18 prompts. Today: 1h 5m across 2 sessions, no breaks yet. Might want to think about one soon. /breather:pause saves your spot.

   **90+ min today, no break:** Direct but not preachy.
   > This session: 40m, 24 prompts. Today: 1h 35m across 3 sessions, 0 breaks. That's past the point where error rates start climbing. /breather:pause saves your context if you want to step away.

   **120+ min today, no break:** Matter-of-fact urgency.
   > This session: 55m. Today: 2h 10m across 2 sessions, 0 breaks. You've been at this for over 2 hours. The code will be here when you get back. /breather:pause

4. **Never:** use guilt, be condescending, reference "self-care" or "wellness", or compare the user to statistics. Just state the numbers and make a practical suggestion.
