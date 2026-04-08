#!/bin/bash
# Sync local dev changes to Claude Code plugin cache
# Reads version from plugin.json so the cache path matches what Claude Code expects
set -euo pipefail

VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
CACHE_DIR="$HOME/.claude/plugins/cache/jessedegans-plugins/breather/$VERSION"

# Clean cache first so deleted files don't linger
rm -rf "$CACHE_DIR"
mkdir -p "$CACHE_DIR"
cp -r hooks scripts skills commands .claude-plugin README.md LICENSE "$CACHE_DIR/"
chmod +x "$CACHE_DIR"/scripts/*.sh

# Also update the stable statusline copy if setup was run
if [ -f ~/.claude/breather-statusline.sh ]; then
  cp scripts/statusline.sh ~/.claude/breather-statusline.sh
  cp scripts/breather-lib.sh ~/.claude/breather-lib.sh
  chmod +x ~/.claude/breather-statusline.sh ~/.claude/breather-lib.sh
fi

echo "Synced to $CACHE_DIR (v$VERSION)"
