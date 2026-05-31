# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles for macOS/zsh. Managed with a simple `install.sh` bootstrap script.

## Structure

- `.zshrc` — Main zsh config: Oh My Zsh with `robbyrussell` theme, plugins (`git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`), and N-Claude profile setup
- `install.sh` — Bootstrap script that symlinks dotfiles and generates secret-bearing configs
- `.claude/` — Claude Code config for the default profile (`~/.claude`)
- `.claude-second-profile/` — Claude Code config for a second profile (`~/.claude-second-profile`)
- `.claude-third-profile/` — Claude Code config for a third profile (`~/.claude-third-profile`), pointed at an alternate Anthropic-compatible provider
- `.githooks/` — Git hooks directory (configured via `core.hooksPath`)

## N-Claude Profile System

The `.zshrc` defines a `_claude_with_profile` helper and wrapper functions to switch between Claude profiles via `CLAUDE_CONFIG_DIR`:

```zsh
claude()    # uses ~/.claude (default)
s-claude()  # uses ~/.claude-second-profile
d-claude()  # uses ~/.claude-third-profile (alternate provider)
```

### Adding a New Profile

1. Add entry to `_claude_profiles` array in `.zshrc`
2. Add `setup_profile "<dir>" "<ENV_VAR>"` call in `install.sh`
3. Create `<dir>/settings.json` and `<dir>/CLAUDE.md` in the repo

The `install.sh` symlinks each profile's `CLAUDE.md` to `$HOME`, so edits in the repo take effect immediately after re-running install.

## Install

```bash
# Set required env vars first
export Z_AI_AUTH_TOKEN="..."        # for s-claude
export XIAOMI_AUTH_TOKEN="..."      # for d-claude

./install.sh
```

The script symlinks dotfiles into `$HOME` and generates `settings.json` for each profile, injecting the auth token from the corresponding env var. It also configures git to use `.githooks/` via `core.hooksPath`.

## Git Hooks

- `post-checkout` — Copies `.env` from main worktree to new worktrees (for `git worktree add`)

## Security

All profile `settings.json` files share a deny list that blocks destructive `rm` commands and reads of `.env`, SSH/AWS configs, credentials, secrets, and key/pem files. See any `*/settings.json` for the canonical list.
