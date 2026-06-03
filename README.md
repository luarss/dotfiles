# Dotfiles

Personal macOS/zsh dotfiles, bootstrapped with `install.sh`.

## Install

```bash
# Set token env vars referenced by providers.json (see .env.example)
export DEEPSEEK_AUTH_TOKEN="..."    # s-claude / cl deepseek
export XIAOMI_AUTH_TOKEN="..."      # d-claude / cl mimo

./install.sh
```

Symlinks dotfiles into `$HOME`, generates each Claude profile's `settings.json`
and the zsh wrappers from `providers.json`, and points git at `.githooks/`.

## Contents

- `.zshrc` — Oh My Zsh config; sources the generated Claude profile wrappers
- `providers.json` — single source of truth for Claude profiles
- `settings.base.json` — shared `settings.json` content for every profile
- `gen-settings.jq` — layers base + provider into each profile's `settings.json`
- `install.sh` — bootstrap script
- `.githooks/` — git hooks (`core.hooksPath`)

## Claude Profiles

Profiles are driven by `providers.json`. Select one (each sets `CLAUDE_CONFIG_DIR`):

```zsh
claude       # ~/.claude (default)
s-claude     # ~/.claude-second-profile
d-claude     # ~/.claude-third-profile
cl mimo      # any provider by manifest key
cl --list    # list providers
```

To add a provider: add an entry to `providers.json`, add its token to `.env`,
then run `./install.sh`. See [AGENTS.md](AGENTS.md) for details.
