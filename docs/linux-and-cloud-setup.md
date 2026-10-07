# Linux & Claude Code Cloud Setup

`install.sh` detects Linux via `uname` and installs a scoped subset. The same path serves the Claude Code cloud sandbox (claude.ai/code) and any regular Linux machine.

## What installs on Linux

- `~/.zshrc` — a real file containing `source "$DOTFILES/.zshrc"` (not a symlink, for bwrap compatibility)
- `~/.claude/settings.json` — default profile only
- `~/.claude` hooks, skills, and commands

Skipped (Darwin-only): second/third profiles and the `cl` dispatcher, plugin lock, zsh plugins, npm tools, launchd agents, Antigravity, Ghostty, Finder defaults, rtk.

## Requirements

`bash`, `git`, `jq`. No auth tokens are needed — the default profile is first-party.

## Claude Code cloud environment

In the environment settings, paste into **Setup script**:

```bash
#!/bin/bash
set -u
DOTFILES="$HOME/dotfiles"
command -v jq >/dev/null || (apt-get update -qq && apt-get install -y -qq jq)
if [ ! -d "$DOTFILES" ]; then
  git clone --depth=1 https://github.com/luarss/dotfiles.git "$DOTFILES"
fi
"$DOTFILES/install.sh" || echo "dotfiles install failed; continuing"
```

**Environment variables** (visible to anyone using the environment — never put secrets here):

```
GIT_AUTHOR_NAME=luarss
GIT_AUTHOR_EMAIL=39641663+luarss@users.noreply.github.com
GIT_COMMITTER_NAME=luarss
GIT_COMMITTER_EMAIL=39641663+luarss@users.noreply.github.com
```

Notes:

- The sandbox's git proxy may only authorize repos selected for the session. If the repo is private and the clone fails, either make it public or add it to the session and point `DOTFILES` at its checkout path.
- `|| echo` keeps a failed install from blocking session start.
- rtk's hook no-ops on non-Darwin; the security guards and `no-claude-trailer.sh` still apply.

## Regular Linux machines

```bash
git clone https://github.com/luarss/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Caveats:

- The `apt-get` line above assumes Debian/Ubuntu and root. Elsewhere, install `jq` with `sudo` or your distro's package manager.
- `.zshrc` sources Oh My Zsh unconditionally; install Oh My Zsh first if you use zsh interactively, or the shell prints an error on startup.

## Cleanup

`scripts/reset-linux.sh` removes artifacts left by older (pre-scoped) installs. Dry run by default; `-f` to delete.
