---
name: checkin
description: Use when the user asks "how am I doing", "session status", "how long have I been working", "check in", "checkin", "am I overdue for a break", or wants to know their current session stats.
allowed-tools: Read, Bash
---

# Check In - Session Status

Provide an honest, non-preachy assessment of the current session.

## Steps

1. **Read session state** from `${CLAUDE_PLUGIN_DATA:-~/.local/share/breather}/current-session.json`

2. **Calculate key metrics:**
   - Total session duration (from start_ts)
   - Time since last break (from last_break_ts)
   - Prompt count
   - Full breaks (full_breaks) and stretches (quick_breaks)

3. **Assess the session** and respond with a brief status. Tone depends on the numbers:

   **Under 50 min, breaks taken:** Just the facts, positive.
   > Session: 42m, 18 prompts, 1 full break, 3 stretches. You're in good shape.

   **50-90 min, no break:** Neutral observation.
   > Session: 1h 5m, 28 prompts, no breaks yet. Might want to think about one soon. /breather:pause saves your spot.

   **90+ min, no break:** Direct but not preachy.
   > Session: 1h 35m, 42 prompts, 0 breaks. That's past the point where research shows error rates start climbing. Your brain is working harder than you think. /breather:pause saves your context if you want to step away.

   **120+ min, no break:** Matter-of-fact urgency.
   > Session: 2h 10m, 58 prompts, 0 breaks. You've been in this chair for over 2 hours straight. The code will be here when you get back. /breather:pause

4. **If prompted by /loop** (not explicitly by the user), keep it to 1-2 sentences woven into whatever you're already doing. Don't make a separate announcement.

5. **Never:** use guilt, be condescending, reference "self-care" or "wellness", or compare the user to statistics. Just state the numbers and make a practical suggestion.
