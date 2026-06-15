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
- `.claude/`, `.claude-second-profile/`, `.claude-third-profile/` — Per-profile dirs (`CLAUDE.md`, hooks, etc.). Their `settings.json` is **generated**, not committed. The default `.claude/` profile also ships `RTK.md` (rtk meta-command reference).
- `.githooks/` — Git hooks directory (configured via `core.hooksPath`)
- `routines/` — Backup of remote routines (scheduled cloud agents at claude.ai). One dir per routine holding `SKILL.md` (prompt + schedule in frontmatter). Synced from the server with the `/sync-routines` slash command — routines live server-side and are only reachable via the `RemoteTrigger` tool, so the sync must be Claude-driven; there is no curl/cron path. **The repo is public**: only name/schedule/prompt are stored, never `routine.json` or trigger/environment/connector/account IDs. `install.sh` symlinks them into `~/.claude/scheduled-tasks/` **only when `hostname -s` matches the work hostname** (`DOTFILES_WORK_HOSTNAME`, default `Shuis-MacBook-Air`) and prunes symlinks for routines deleted from the repo; personal machines skip them.

## N-Claude Profile System

Everything is driven by `providers.json`. On install, `install.sh`:

1. Generates each profile's `~/<dir>/settings.json` from `settings.base.json` + the provider entry (injecting the auth token from its `token` env var).
2. Generates `~/.claude-profiles.zsh` — a `cl <provider>` dispatcher plus the short aliases — which `.zshrc` sources.

Selecting a provider (each sets `CLAUDE_CONFIG_DIR` to its dir):

```zsh
claude       # ~/.claude (default)               ┐ short aliases, from each
s-claude     # ~/.claude-second-profile          │ provider's `aliases` list
d-claude     # ~/.claude-third-profile           ┘
cl mimo          # dispatcher: any provider by manifest key
cl --list        # list available providers
```

### rtk (Rust Token Killer) — default profile

The default `claude` profile (`.claude`) has [rtk](https://github.com/rtk-ai/rtk) wired in for token-saving command rewrites. `rtk` itself is installed via the `Brewfile` (`brew "rtk"`). It lives **only** in the default profile, so the third-party profiles (`s-claude`, `d-claude`) stay untouched:

- Its `overrides.hooks.PreToolUse` re-declares the shared guards (`remote-command-guard.sh`, `db-guard.sh`, `db-rate-limit.sh`) **plus** `rtk hook claude`, which transparently rewrites Bash commands (`git status` → `rtk git status`). The rtk hook is listed **last** so the security guards inspect the original command first. (The `mcp__.*mysql.*` matcher carrying `db-rate-limit.sh` is re-declared here too.)
- `.claude/CLAUDE.md` `@`-imports `RTK.md` — the rtk meta-command reference (`rtk gain`, `rtk discover`, `rtk proxy`). `install.sh` symlinks `RTK.md` into a profile only when that profile ships one (only the default does).
- **Telemetry is disabled** two ways: `overrides.env.RTK_TELEMETRY_DISABLED=1` in `providers.json` (covers the in-Claude hook), and `export RTK_TELEMETRY_DISABLED=1` in `.zshrc` (covers manual `rtk` use in the shell). rtk telemetry is also off by default / opt-in, so this just makes the opt-out explicit and reproducible.

After install, **restart Claude Code** for the hook to take effect.

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

`settings.base.json` registers `PreToolUse` hooks (all exit 2 to deny). Three run on the `Bash` matcher, and one (`db-rate-limit.sh`) also runs on an `mcp__.*mysql.*` matcher:

- `.claude/hooks/db-guard.sh` — blocks destructive SQL run through the `mysql`/`mariadb`/`psql` CLIs: `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE`, `DELETE` without `WHERE`, and `ALTER TABLE ... DROP`. It only inspects inline SQL in the command string; SQL loaded from a file (`psql -f`) is not checked.
- `.claude/hooks/db-rate-limit.sh` — sliding-window rate limiter for MySQL access: blocks once more than **20 qualifying calls happen within 60s** (edit `LIMIT`/`WINDOW` at the top of the script). It counts two call types: `mysql`/`mariadb` CLI invoked to run a statement (a client token followed by `-e`/`--execute` or a heredoc, mirroring `db-guard`'s detection) via the `Bash` matcher, and `mcp__*mysql*` MCP tool calls via the `mcp__.*mysql.*` matcher. Counts are kept per-machine in a timestamp log under `$TMPDIR/claude-mysql-ratelimit/`; entries older than the window are pruned on every call, so the limiter self-heals and needs no cleanup. The block message reports how long to wait before the oldest in-window call expires.
- `.claude/hooks/remote-command-guard.sh` — blocks dangerous Bash across 7 categories (destructive deletion, env/secret leakage, path traversal, external comms, permission changes, process termination, command injection). **It only fires in orchestrated/remote sessions** — i.e. when `OPENCLAW_SESSION_ID` or `HERMES_SESSION_ID` is set — and no-ops in normal interactive local sessions so day-to-day `curl`/`ssh`/`sudo`/`kill` stay allowed. This complements the `Read(...)` deny rules, which only cover file-reading commands Claude recognizes (`cat`/`head`/`tail`/`sed`/`grep`) and not `env`/`printenv`/`echo $VAR` or indirect readers. The env/secret-leakage category is broad: env/`set`/`declare -p` dumps; `echo`/`printf` of secret-ish vars (incl. `${VAR}`); reading `.env`/`credentials`/`secrets.*` via **any** reader; and references to cloud-cred files (`~/.aws`, `~/.ssh` except `known_hosts`, `~/.kube`, `~/.config/gcloud`, `.git-credentials`, `.pgpass`, `.netrc`), shell history, private keys, and the macOS keychain. Benign vars like `$PATH`/`$PWD` and `.env.example` templates are deliberately allowed.

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

**npm CLI tools** (`tools/`, installed by `install_node_tools` in `install.sh`) — exact versions in `tools/package.json`; the committed lockfile carries sha512 integrity pins verified by `npm ci`. Binaries are symlinked into `~/.local/bin` — never alias to `npx <pkg>`. To bump: edit `tools/package.json`, `npm install --package-lock-only`, commit, re-run `./install.sh`.
Pinned: `ccusage` 20.0.9

**Homebrew** — no true version lock exists; `brew bundle` doesn't generate one. Use `brew bundle install --no-upgrade` to prevent silent upgrades on fresh installs. Audit third-party taps (`hashicorp/tap`) before adding — prefer taps owned by the upstream vendor.

**Claude plugins** — `installed_plugins.json` is committed to this repo and symlinked to `~/.claude/plugins/installed_plugins.json` by `install.sh`. It records the `gitCommitSha` for every installed plugin. To check for updates run `scripts/check-plugin-updates.sh` (also runs weekly via `.github/workflows/check-plugin-updates.yml`, which opens a GitHub issue when any plugin is behind). To update a plugin: let Claude Code upgrade it, copy the updated `~/.claude/plugins/installed_plugins.json` back into the repo, and commit.
