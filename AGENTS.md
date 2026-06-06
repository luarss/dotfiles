# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles for macOS/zsh. Managed with a simple `install.sh` bootstrap script.

## Structure

- `.zshrc` — Main zsh config: Oh My Zsh with `robbyrussell` theme, plugins (`git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`); sources the generated N-Claude profile wrappers
- `install.sh` — Bootstrap script that symlinks dotfiles and generates per-profile configs
- `providers.json` — **Single source of truth** for Claude profiles: one entry per provider (dir, aliases, token env var, base URL, model map, freeform settings `overrides`)
- `settings.base.json` — Shared `settings.json` content for every profile (deny list, hooks, status line, plugins, attribution)
- `gen-settings.jq` — jq program that layers `settings.base.json` + a provider's env/overrides into a final `settings.json`
- `.claude/`, `.claude-second-profile/`, `.claude-third-profile/` — Per-profile dirs (`CLAUDE.md`, hooks, etc.). Their `settings.json` is **generated**, not committed.
- `.githooks/` — Git hooks directory (configured via `core.hooksPath`)

## N-Claude Profile System

Everything is driven by `providers.json`. On install, `install.sh`:

1. Generates each profile's `~/<dir>/settings.json` from `settings.base.json` + the provider entry (injecting the auth token from its `token` env var).
2. Generates `~/.claude-profiles.zsh` — a `cl <provider>` dispatcher plus the short aliases — which `.zshrc` sources.

Selecting a provider (each sets `CLAUDE_CONFIG_DIR` to its dir):

```zsh
claude       # ~/.claude (default)              ┐ short aliases, from each
s-claude     # ~/.claude-second-profile          │ provider's `aliases` list
d-claude     # ~/.claude-third-profile           ┘
cl mimo          # dispatcher: any provider by manifest key
cl --list        # list available providers
```

### Adding a New Provider

1. Add one entry to `providers.json` (`dir`, `aliases`, `token`, and for third-party providers `thirdParty: true` + `baseUrl` + `models`).
2. Add the `token` value to `.env` (and mirror the empty key in `.env.example`).
3. Run `./install.sh`.

No edits to `.zshrc`, `install.sh`, or any `settings.json` are needed — they all derive from the manifest. The `models` field accepts a string (applied to all tiers incl. `ANTHROPIC_MODEL`) or an object with `haiku`/`sonnet`/`opus`/`default` keys.

## Install

```bash
# Set the token env vars referenced by providers.json first (see .env.example)
export DEEPSEEK_AUTH_TOKEN="..."    # for s-claude / cl deepseek
export XIAOMI_AUTH_TOKEN="..."      # for d-claude / cl mimo

./install.sh
```

The script symlinks dotfiles into `$HOME`, generates each profile's `settings.json` and the zsh wrappers from `providers.json`, and configures git to use `.githooks/` via `core.hooksPath`. It also symlinks each profile's `CLAUDE.md` and `AGENTS.md`, so repo edits take effect after re-running install.

## Git Hooks

- `post-checkout` — Copies `.env` from main worktree to new worktrees (for `git worktree add`)

## Security

Every profile's `settings.json` is generated from `settings.base.json`, which carries the shared deny list blocking destructive `rm` commands and reads of `.env`, SSH/AWS configs, credentials, secrets, and key/pem files. Edit `settings.base.json` to change the policy for all profiles at once.

## Dependency Locking (Supply Chain Hygiene)

Pin every external dependency to an immutable reference. Never use mutable tags or branches in any automated install path.

**GitHub Actions** — pin to a full commit SHA, not a tag. Annotate with the tag for readability.
```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```
Resolve: `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha`
Currently unpinned: `actions/checkout` in `.github/workflows/test.yml`

**Zsh plugins** (`install_zsh_plugin` in `install.sh`) — clone at a specific tag and assert the SHA:
```bash
git clone --depth=1 --branch <tag> "https://github.com/$repo.git" "$plugin_dir"
actual=$(git -C "$plugin_dir" rev-parse HEAD)
[ "$actual" = "<expected-sha>" ] || { echo "SHA mismatch for $repo"; exit 1; }
```
Pinned: `zsh-users/zsh-autosuggestions` v0.7.1, `zsh-users/zsh-syntax-highlighting` 0.8.0

**Homebrew** — no true version lock exists; `brew bundle` doesn't generate one. Use `brew bundle install --no-upgrade` to prevent silent upgrades on fresh installs. Audit third-party taps (`hashicorp/tap`) before adding — prefer taps owned by the upstream vendor.
