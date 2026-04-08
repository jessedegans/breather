---
name: breather-setup
description: First-time setup for breather. Run once after installing.
---

# Breather Setup

One-time setup. Run this once after installing the plugin.

## Steps

1. **Check if already set up.** Read `~/.claude/settings.json`. If it already contains a `statusLine` entry with "breather" in the command, tell the user setup is already done and skip everything.

2. **Introduce and explain what setup will do:**

   > **Breather** tracks how long you've been working across all your terminals, nudges you to take breaks, and saves your mental context so stopping doesn't cost you anything.
   >
   > Everything except the status bar already works. Setup will:
   >
   > 1. **Add a status bar** at the bottom of your terminal (session time, daily total, break count)
   > 2. **Auto-allow break recording scripts** so `/breather:pause` and `/breather:stretch` record instantly without permission prompts. This matters because if you walk away right after saying "pause," a permission prompt would block the recording.
   >
   > The scripts being auto-allowed are:
   > - `record-break.sh` (records a full break)
   > - `record-stretch.sh` (records a quick stretch)
   > - `daily-stats.sh` (reads your session stats)
   >
   > OK to proceed?

   Wait for the user to confirm.

3. **Create the statusline wrapper script** at `~/.claude/breather-statusline.sh`:
   ```bash
   #!/bin/bash
   # Breather statusline wrapper. Finds and runs the real script.
   # Survives plugin version updates without re-running setup.
   REAL=$(find ~/.claude/plugins/cache -path "*/breather/*/scripts/statusline.sh" -print -quit 2>/dev/null)
   if [ -n "$REAL" ]; then
     exec bash "$REAL"
   fi
   ```
   Make it executable with `chmod +x ~/.claude/breather-statusline.sh`.

4. **Read** `~/.claude/settings.json`.

5. **Add the statusline** config to settings.json:
   ```json
   "statusLine": {
     "type": "command",
     "command": "bash ~/.claude/breather-statusline.sh"
   }
   ```

6. **Add auto-allow entries** to `permissions.allow` in settings.json:
   ```json
   "Bash(*/breather/scripts/record-break.sh)",
   "Bash(*/breather/scripts/record-stretch.sh)",
   "Bash(*/breather/scripts/daily-stats.sh)"
   ```
   Preserve any existing allow rules. Do not add duplicates.

7. **Write the updated settings.json.**

8. **Wrap up:**

   > Done. Restart Claude Code to see the status bar.
   >
   > The bar shows: session time, daily total (green/yellow/red by fatigue), and break count.
   > I'll start nudging you after 25 minutes of continuous work.
   >
   > `/breather:pause` when you want to stop, `/breather:back` when you return.
