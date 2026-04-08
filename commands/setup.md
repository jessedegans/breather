---
name: breather-setup
description: First-time setup for breather. Run once after installing.
---

# Breather Setup

One-time setup. Run this once after installing the plugin.

## Steps

1. **Introduce yourself first.** Before doing anything, explain what breather is and what this setup will do:

   > **Breather** is an automatic break reminder for Claude Code. It tracks how long you've been working across all your terminals, nudges you to take breaks, and saves your mental context so stopping doesn't cost you 20 minutes of "where was I?"
   >
   > This setup does two things:
   > 1. Adds a status line at the bottom of your terminal showing your session time and daily total
   > 2. Optionally auto-allows the break recording scripts so pausing works instantly
   >
   > After setup, everything runs automatically. Ready?

   Wait for the user to confirm before proceeding.

2. **Copy the statusline script** to a stable location (survives plugin updates):
   ```bash
   cp "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh" ~/.claude/breather-statusline.sh && cp "${CLAUDE_PLUGIN_ROOT}/scripts/breather-lib.sh" ~/.claude/breather-lib.sh && chmod +x ~/.claude/breather-statusline.sh ~/.claude/breather-lib.sh
   ```

3. **Read** `~/.claude/settings.json`.

4. **Add the statusline** config. Add or update the `statusLine` key:
   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/breather-statusline.sh"
   }
   ```

5. **Explain auto-allow and ask:**

   > The break recording scripts (`record-break.sh`, `record-stretch.sh`, `daily-stats.sh`) need permission to run each time by default. I can auto-allow them so `/breather:pause` records instantly without prompting.
   >
   > This matters because if you walk away right after saying "pause," a permission prompt would block and the break is never recorded.
   >
   > **Auto-allow these scripts?** (yes/no)

6. **If yes**, add to `permissions.allow` in settings.json:
   ```json
   "Bash(*/breather/scripts/record-break.sh)",
   "Bash(*/breather/scripts/record-stretch.sh)",
   "Bash(*/breather/scripts/daily-stats.sh)"
   ```
   Preserve any existing allow rules.

7. **Write the updated settings.json.**

8. **Wrap up:**

   > Setup complete. Here's what you have now:
   >
   > - **Status line**: shows session time and daily total (green/yellow/red based on fatigue)
   > - **Automatic nudges**: eye break at 25 min, stretch at 50 min, real break at 90 min
   > - **Commands**: `/breather:pause` (full break with context save), `/breather:stretch` (quick break), `/breather:back` (restore context), `/breather:checkin` (stats), `/breather:reflect` (end of day summary)
   >
   > Restart Claude Code to see the status line. Everything else works right away.
