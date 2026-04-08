---
name: setup
description: First-time setup for breather. Run once after installing.
---

# Breather Setup

One-time setup. Configures the status line and optionally auto-allows break recording scripts.

## Steps

1. **Copy the statusline script** to a stable location (survives version updates):
   ```bash
   cp "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh" ~/.claude/breather-statusline.sh && cp "${CLAUDE_PLUGIN_ROOT}/scripts/breather-lib.sh" ~/.claude/breather-lib.sh && chmod +x ~/.claude/breather-statusline.sh ~/.claude/breather-lib.sh
   ```

2. **Read** `~/.claude/settings.json`.

3. **Add the statusline** config. Add or update the `statusLine` key:
   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/breather-statusline.sh"
   }
   ```

4. **Explain auto-allow and ask the user:**

   > Breather uses small scripts to record breaks and read session stats. By default, Claude Code asks for permission each time one runs.
   >
   > I can auto-allow these specific scripts so `/breather:pause` and `/breather:stretch` record instantly. This is recommended. Otherwise you'll need to approve each time, and if you walk away after saying "pause", the break won't be recorded.
   >
   > Scripts that would be auto-allowed:
   > - `record-break.sh` (records a full break)
   > - `record-stretch.sh` (records a quick stretch)
   > - `daily-stats.sh` (reads session stats)
   >
   > **Auto-allow these?** (yes/no)

5. **If yes**, add to `permissions.allow` in settings.json:
   ```json
   "Bash(*/breather/scripts/record-break.sh)",
   "Bash(*/breather/scripts/record-stretch.sh)",
   "Bash(*/breather/scripts/daily-stats.sh)"
   ```
   Preserve any existing allow rules.

6. **Write the updated settings.json.**

7. **Give a brief intro:**

   > Breather is set up. Here's what happens now:
   >
   > - The status line at the bottom shows your session time and daily total (green/yellow/red)
   > - After 25 min, I'll suggest an eye break. After 50, a stretch. After 90, a real break.
   > - `/breather:pause` saves your mental context so you can stop without losing your place
   > - `/breather:stretch` for a quick break, `/breather:back` to pick up where you left off
   > - `/breather:checkin` for session stats, `/breather:reflect` for end-of-day summary
   >
   > Restart Claude Code to see the status line. Everything else is automatic.
