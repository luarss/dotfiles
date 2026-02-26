# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles for macOS/zsh. Managed with a simple `install.sh` bootstrap script.

## Structure

- `.zshrc` — Main zsh config: Oh My Zsh with `robbyrussell` theme, plugins (`git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`), and dual Claude profile setup
- `install.sh` — Bootstrap script (currently a stub; symlink logic goes here)
- `.claude/` — Claude Code config for the default profile (`~/.claude`)
- `.claude-second-profile/` — Claude Code config for a second profile (`~/.claude-second-profile`)

## Dual Claude Profile System

The `.zshrc` defines two shell functions to switch between Claude profiles via `CLAUDE_CONFIG_DIR`:

```zsh
claude()    # uses ~/.claude (default)
s-claude()  # uses ~/.claude-second-profile
```

Each profile directory contains its own `CLAUDE.md` with shared global preferences.

## Install

```bash
./install.sh
```

The script should symlink dotfiles from this repo into `$HOME`. When extending it, prefer symlinks over copying so edits to the repo take effect immediately.
