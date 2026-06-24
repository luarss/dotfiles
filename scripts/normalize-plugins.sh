#!/usr/bin/env bash
# Copy the live installed_plugins.json back into the repo with $HOME → ~
# so installPath values stay machine-agnostic in version control.
#
# Run this after Claude Code installs or updates a plugin, then commit.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$HOME/.claude/plugins/installed_plugins.json"
dst="$DOTFILES/installed_plugins.json"

if [ ! -f "$src" ]; then
  echo "ERROR: $src not found" >&2
  exit 1
fi

sed "s|$HOME|~|g" "$src" > "$dst"
echo "NORMALIZED  $dst  (\$HOME → ~)"
