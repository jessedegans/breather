---
name: setup-statusline
description: Set up the breather status line in your Claude Code settings. Run once after installing the plugin.
---

# Set up breather status line

Add the breather session timer to your Claude Code status bar.

## What this does

Adds a `statusLine` entry to your `~/.claude/settings.json` that points to breather's statusline script. This shows a color-coded session timer at the bottom of every Claude Code session.

## Steps

1. Read `~/.claude/settings.json`
2. Check if a `statusLine` entry already exists
3. If it does, ask the user if they want to replace it
4. If not, add the breather statusline configuration
5. Write the updated settings back

## The configuration to add

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/plugins/cache/jessedegans-plugins/breather/0.1.0/scripts/statusline.sh"
  }
}
```

## After adding

Tell the user:

> Status line configured. Restart Claude Code to see the session timer.
>
> What you'll see: a color-coded timer (green < 50 min, yellow 50-90 min, red 90+ min) and break count at the bottom of your terminal.
>
> To remove it later, delete the `statusLine` key from `~/.claude/settings.json`.
