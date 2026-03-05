# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles for macOS/zsh. Managed with a simple `install.sh` bootstrap script.

## Structure

- `.zshrc` — Main zsh config: Oh My Zsh with `robbyrussell` theme, plugins (`git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`), and N-Claude profile setup
- `install.sh` — Bootstrap script that symlinks dotfiles and generates secret-bearing configs
- `.claude/` — Claude Code config for the default profile (`~/.claude`)
- `.claude-second-profile/` — Claude Code config for a second profile (`~/.claude-second-profile`)
- `.claude-third-profile/` — Claude Code config for DashScope/Aliyun profile (`~/.claude-third-profile`)
- `.githooks/` — Git hooks directory (configured via `core.hooksPath`)

## N-Claude Profile System

The `.zshrc` defines a `_claude_with_profile` helper and wrapper functions to switch between Claude profiles via `CLAUDE_CONFIG_DIR`:

```zsh
claude()    # uses ~/.claude (default)
s-claude()  # uses ~/.claude-second-profile
d-claude()  # uses ~/.claude-third-profile (DashScope/Aliyun)
```

To add more profiles, create a new wrapper function following the same pattern. Each profile directory contains its own `CLAUDE.md` with shared global preferences.

## Install

```bash
./install.sh
```

The script symlinks dotfiles into `$HOME` and:
- Generates `.claude-second-profile/settings.json` with `ANTHROPIC_AUTH_TOKEN` from `Z_AI_AUTH_TOKEN` env var
- Generates `.claude-third-profile/settings.json` with `ANTHROPIC_AUTH_TOKEN` from `DASHSCOPE_AUTH_TOKEN` env var
- Configures git to use `.githooks/` via `core.hooksPath`

When extending, prefer symlinks over copying so edits to the repo take effect immediately.

## Git Hooks

- `post-checkout` — Copies `.env` from main worktree to new worktrees (for `git worktree add`)
