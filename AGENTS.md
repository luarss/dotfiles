# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles for macOS/zsh. Managed with a simple `install.sh` bootstrap script. **Primarily macOS** — the multi-profile Claude/zsh setup (second/third profiles, the `cl` dispatcher) targets the dev laptop and stays Darwin-only. On Linux (e.g. the bwrap sandbox used by remote/orchestrated sessions) `install.sh` installs a scoped subset instead: `~/.zshrc` (see N-Claude Profile System note below) and the default Claude Code profile (`settings.json`, hooks, skills, commands) — everything else (other profiles, plugin lock) is skipped.

## Structure

- `.zshrc` — Main zsh config: Oh My Zsh with `robbyrussell` theme, plugins (`git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`); sources the generated N-Claude profile wrappers
- `install.sh` — Bootstrap script that symlinks dotfiles and generates per-profile configs
- `providers.json` — **Single source of truth** for Claude profiles: one entry per provider (dir, aliases, token env var, base URL, model map, freeform settings `overrides`)
- `settings.base.json` — Shared `settings.json` content for every profile (deny list, hooks, status line, plugins, attribution)
- `gen-settings.jq` — jq program that layers `settings.base.json` + a provider's env/overrides into a final `settings.json`

- `.claude/`, `.claude-second-profile/`, `.claude-third-profile/` — Per-profile dirs (`CLAUDE.md`, hooks, etc.). Their `settings.json` is **generated**, not committed. The default `.claude/` profile also ships `RTK.md` (rtk meta-command reference).
- `.githooks/` — Git hooks directory (configured via `core.hooksPath`)

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

- Its `overrides.hooks.PreToolUse` re-declares the shared guards (`remote-command-guard.sh`, `db-guard.sh`, `db-rate-limit.sh`) **plus** the work-laptop `skill-scan-guard.sh` (see Security) **plus** `.claude/hooks/rtk-hook.sh`, which wraps `rtk hook claude` and transparently rewrites Bash commands (`git status` → `rtk git status`). The rtk hook is listed **last** so the security guards inspect the original command first. (The `mcp__.*mysql.*` matcher carrying `db-rate-limit.sh` is re-declared here too.) The wrapper no-ops on non-Darwin so Linux machines aren't broken by a missing `rtk` binary.
- `.claude/RTK.md` — the rtk meta-command reference (`rtk gain`, `rtk discover`, `rtk proxy`). `install.sh` symlinks it and generates `~/.claude/CLAUDE.md` with `@RTK.md` included, gated to Darwin in `generate_profiles` (see Install). On Linux neither happens, so rtk context never loads there.
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

On macOS the script symlinks dotfiles into `$HOME`, generates every profile's `settings.json` and the zsh wrappers from `providers.json`, and configures git to use `.githooks/` via `core.hooksPath`. It also symlinks each profile's `AGENTS.md`. `CLAUDE.md` is symlinked, except for profiles with `RTK.md` where it is generated (with `@RTK.md` appended) — re-run install after editing `.claude/CLAUDE.md`. On Linux it installs only the default profile's settings/hooks/skills/commands, plus `~/.zshrc`.

`~/.zshrc` itself is installed differently per OS (`setup_zsh_config` in `install.sh`): on macOS it's a plain symlink (edits are live); on Linux it's a real file containing `source "$DOTFILES/.zshrc"`, deliberately **not** a symlink — bwrap (the sandbox this path targets) follows symlinks when precomputing its tmpfs bind-mount points, so a symlink to an unmounted target fails with ENOENT, while a real file only needs bwrap to resolve two concrete paths. RTK.md/rtk stay Darwin-only regardless, since rtk is a Homebrew-only binary and `.zshrc` has no rtk-specific content.

To clean up artifacts an older (pre-scoped) `install.sh` left on a Linux box, run `scripts/reset-linux.sh` there (dry run by default; `-f` to remove). It deletes only the repo-owned ZDOTDIR `~/.zshenv`, the generated `settings.json`/plugin lock/zsh wrappers, the `.claude-second-profile`/`.claude-third-profile` dirs, and repo symlinks — never your real `~/.claude` data or the current `~/.zshrc` source-file.

## Git Hooks

- `post-checkout` — Copies `.env` from main worktree to new worktrees (for `git worktree add`)

## Daily Session Log (launchd, macOS)

`scripts/daily-session-log.sh` is the batch, non-interactive counterpart to the `/done` skill. A weekday-9am launchd agent runs it to log every Claude Code session under `~/work` into the latest weekly note (`~/work/notes/NUS-Enterprise/Weekly/<WEEK>.md`) and push it straight to the base branch (no PR).

- **Why not `/done` directly:** `/done` needs a model to summarize the conversation and confirms before writing. Cron can't do either. The script keeps the deterministic parts in shell — which sessions, dedup, weekly-note resolution, git, push — and delegates only the per-session summary to a model.
- **Why Gemini, not `claude -p`:** the default profile authenticates via subscription OAuth, which can't refresh from a headless launchd job (`OAuth session expired and could not be refreshed`). The script calls the **Gemini REST API** with a static `GEMINI_API_KEY` (from `.env`, mirrored empty in `.env.example`) instead. Model defaults to `gemini-3.6-flash` (override with `SESSION_LOG_MODEL`). **Session transcripts are sent to Google's Gemini endpoint** to be summarized.
- **Which sessions:** a watermark file (`~/.claude/.daily-session-log.watermark`) tracks the last successful run; each run summarizes only work sessions with activity since then (first run looks back 24h). Sessions are found by encoding `~/work` the way Claude Code names project dirs (`/`→`-`) and selecting `*.jsonl` newer than the watermark via a portable `find -newer` reference file. Same-day reruns are deduped by an invisible `<!-- auto-session-log <id> <date> -->` marker in the note.
- **Cost audit:** every Gemini call is logged as one JSONL line (`type:"call"` with session id, input/output/total tokens, `est_cost_usd`, `logged`, and any `error`), plus a `type:"run"` summary line per run. Token counts come from the API's `usageMetadata`; cost is derived from configurable per-1M rates (`SESSION_LOG_PRICE_IN`/`SESSION_LOG_PRICE_OUT`, default `0.10`/`0.40`) and the rates are recorded in the run line so the log is self-describing. Written to `~/work/notes/logs/session-log-costs.jsonl` (override with `SESSION_LOG_COST_LOG`) — colocated with the notes but written directly, never through the git worktree, so it doesn't disturb the checkout. It's deliberately **not** gitignored: Obsidian's own sync/commit picks it up, so the audit trail is versioned without the script ever committing it.
- **Safety:** all git work happens in a throwaway detached `git worktree` at `origin/<base>`, so the real `~/work/notes` checkout is never touched. The commit is pushed **directly to the base branch** — no branch, no PR. If the push is rejected because `origin/<base>` advanced under the run (the merge-conflict case), it fetches, rebases the commit onto the new base, and retries (up to 5 times); a genuine textual conflict during rebase aborts and fails that run, and the next run retries from a clean base. Test without side effects via `SESSION_LOG_DRY_RUN=1` (does everything except push).
- **Install:** `install_session_log_agent` in `install.sh` generates `~/Library/LaunchAgents/com.<user>.daily-session-log.plist` and `launchctl load -w`s it — **work machine only** (`hostname -s` == `$WORK_HOSTNAME`, like the skill-scan guard), and only when a `~/work/notes` git checkout exists. Logs to `~/.claude/logs/daily-session-log.log`. The script self-guards on `GEMINI_API_KEY` and re-checks the repo, so a missing key just fails that run with a clear message.

## Security

Every profile's `settings.json` is generated from `settings.base.json`, which carries the shared deny list blocking destructive `rm` commands and reads of `.env`, SSH/AWS configs, credentials, secrets, and key/pem files. Edit `settings.base.json` to change the policy for all profiles at once.

`settings.base.json` registers `PreToolUse` hooks (all exit 2 to deny). Three run on the `Bash` matcher, and one (`db-rate-limit.sh`) also runs on an `mcp__.*mysql.*` matcher:

- `.claude/hooks/db-guard.sh` — blocks destructive SQL run through the `mysql`/`mariadb`/`psql` CLIs: `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE`, `DELETE` without `WHERE`, and `ALTER TABLE ... DROP`. It only inspects inline SQL in the command string; SQL loaded from a file (`psql -f`) is not checked.
- `.claude/hooks/db-rate-limit.sh` — sliding-window rate limiter for MySQL access: blocks once more than **20 qualifying calls happen within 60s** (edit `LIMIT`/`WINDOW` at the top of the script). It counts two call types: `mysql`/`mariadb` CLI invoked to run a statement (a client token followed by `-e`/`--execute` or a heredoc, mirroring `db-guard`'s detection) via the `Bash` matcher, and `mcp__*mysql*` MCP tool calls via the `mcp__.*mysql.*` matcher. Counts are kept per-machine in a timestamp log under `$TMPDIR/claude-mysql-ratelimit/`; entries older than the window are pruned on every call, so the limiter self-heals and needs no cleanup. The block message reports how long to wait before the oldest in-window call expires.
- `.claude/hooks/remote-command-guard.sh` — blocks dangerous Bash across 7 categories (destructive deletion, env/secret leakage, path traversal, external comms, permission changes, process termination, command injection). **It only fires in orchestrated/remote sessions** — i.e. when `OPENCLAW_SESSION_ID` or `HERMES_SESSION_ID` is set — and no-ops in normal interactive local sessions so day-to-day `curl`/`ssh`/`sudo`/`kill` stay allowed. This complements the `Read(...)` deny rules, which only cover file-reading commands Claude recognizes (`cat`/`head`/`tail`/`sed`/`grep`) and not `env`/`printenv`/`echo $VAR` or indirect readers. The env/secret-leakage category is broad: env/`set`/`declare -p` dumps; `echo`/`printf` of secret-ish vars (incl. `${VAR}`); reading `.env`/`credentials`/`secrets.*` via **any** reader; and references to cloud-cred files (`~/.aws`, `~/.ssh` except `known_hosts`, `~/.kube`, `~/.config/gcloud`, `.git-credentials`, `.pgpass`, `.netrc`), shell history, private keys, and the macOS keychain. Benign vars like `$PATH`/`$PWD` and `.env.example` templates are deliberately allowed.

`.claude/hooks/skill-scan-guard.sh` is **not** in `settings.base.json` — it is wired **only into the default `.claude` profile** via `providers.json` overrides (listed before `rtk hook claude` so it sees the original command), and runs **only on the work laptop**:

- It vets a Claude plugin/skill with **Trivy** (`trivy fs --scanners vuln,secret,misconfig --format json -q`, installed via the Brewfile — see Dependency Locking) **before** it is installed, blocking (exit 2) on any reported finding — vulnerabilities, secrets, or misconfigurations (unparseable output fails closed; the count is decided from the JSON, not the exit code). Trivy needs **no token**: secret/misconfig scanning is fully offline and the vuln DB is cached locally (`install.sh` pre-warms it on the work machine). Like the sonnet switch, it self-gates on `hostname -s` == `$DOTFILES_WORK_HOSTNAME` (default `Shuis-MacBook-Air`) and no-ops everywhere else, so personal machines never scan. *(Trivy replaced Snyk agent-scan, dropped over vendor-continuity risk; it reads files statically and never installs/executes the target, so vetting can't trigger a `postinstall`.)*
- It fires on `claude plugin install <target>` and `claude plugin marketplace add <target>`. A **local path / SKILL.md** is scanned in place; a **git URL** (`https://….git`, `git@…`, `github:o/r`) is shallow-cloned to a temp dir, scanned, then removed; a **bare marketplace name** has nothing local to fetch so it is allowed with a reminder to scan post-install. Skills cloned by hand (plain `git clone` into `~/.claude/skills`) are out of scope — the same kind of blind spot as `db-guard`'s `psql -f`.
- **Allowlist for trusted internal marketplaces**: targets matching a trusted-marketplace glob skip the scan entirely (globs match the raw target, so all three URL forms — `https://github.com/<org>/*`, `git@github.com:<org>/*`, `github:<org>/*` — are covered). The built-in list is hardcoded to the **nus-etp** org. `SKILL_SCAN_ALLOWLIST` (whitespace/newline-separated shell globs) appends ad-hoc entries without editing the hook.
- **Fail-closed**: if a scannable target is present but the scanner can't run (the `trivy` binary is missing, or it emits no parseable JSON), the install is blocked. No secret is involved — Trivy needs no token — so there is nothing to inject into `settings.json`; run `brew bundle` to install trivy. The scanner command is overridable via `SKILL_SCAN_CMD` (used by the test suite to stub the scan offline).

## Dependency Locking (Supply Chain Hygiene)

Pin every external dependency to an immutable reference. Never use mutable tags or branches in any automated install path.

**GitHub Actions** — pin to a full commit SHA, not a tag. Annotate with the tag for readability.
```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```
Resolve: `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha`
Pinned: `actions/checkout` v4.2.2 (`11bd719…`) in both `test.yml` and `check-plugin-updates.yml`

**Zsh plugins** (`install_zsh_plugin` in `install.sh`) — clone at a specific tag and assert the SHA:
```bash
git clone --depth=1 --branch <tag> "https://github.com/$repo.git" "$plugin_dir"
actual=$(git -C "$plugin_dir" rev-parse HEAD)
[ "$actual" = "<expected-sha>" ] || { echo "SHA mismatch for $repo"; exit 1; }
```
Pinned: `zsh-users/zsh-autosuggestions` v0.7.1, `zsh-users/zsh-syntax-highlighting` 0.8.0

**npm CLI tools** (`tools/`, installed by `install_node_tools` in `install.sh`) — exact versions in `tools/package.json`; the committed lockfile carries sha512 integrity pins verified by `npm ci`. Binaries are symlinked into `~/.local/bin` — never alias to `npx <pkg>`. To bump: edit `tools/package.json`, `npm install --package-lock-only`, commit, re-run `./install.sh`.
Pinned: `ccusage` 20.0.9

**Homebrew** — no true version lock exists; `brew bundle` doesn't generate one. Use `brew bundle install --no-upgrade` to prevent silent upgrades on fresh installs. Audit third-party taps (`hashicorp/tap`) before adding — prefer taps owned by the upstream vendor. `trivy` (the work-laptop skill-scan scanner) rides this same channel — no per-invocation fetch, unlike the `uvx`-delivered scanner it replaced.

**Claude plugins** — `installed_plugins.json` is committed to this repo with `installPath` values using `~` as a placeholder. `install.sh` **copies** (not symlinks) it to `~/.claude/plugins/installed_plugins.json`, expanding `~` → `$HOME` at copy time so paths are valid on the current machine. This keeps the repo file as a pinned snapshot: `gitCommitSha` values only change when the user deliberately updates them, and machine-specific absolute paths never leak into version control. It records the `gitCommitSha` for every installed plugin. To check for updates run `scripts/check-plugin-updates.sh` (also runs weekly via `.github/workflows/check-plugin-updates.yml`, which opens a GitHub issue when any plugin is behind). To update a plugin: let Claude Code upgrade it, then run `scripts/normalize-plugins.sh` to copy the updated file back into the repo with paths normalized to `~`, and commit.
