#!/bin/bash -eu
# daily-session-log.sh — weekday 9am routine (launchd) that logs each Claude Code
# session run under ~/work into the latest weekly note and opens a PR.
#
# It is the batch, non-interactive counterpart to the /done skill. /done can't run
# in cron: it needs a model to summarize a conversation and it confirms before
# writing. So this script keeps the deterministic parts in shell (which sessions,
# dedup, weekly-note resolution, git, PR) and delegates ONLY the summary of each
# session to the Gemini API — one call per session, mirroring /done. (Claude's
# subscription OAuth can't refresh from a launchd job, so a first-party `claude -p`
# isn't viable here; the Gemini REST API uses a static GEMINI_API_KEY instead.)
#
# NOTE: session transcripts are sent to Google's Gemini endpoint to be summarized.
#
# Safety: all git work happens in a throwaway `git worktree`, so the user's real
# ~/work/notes checkout (branch, working tree) is never touched.
#
# Env knobs (all optional):
#   SESSION_LOG_DRY_RUN=1    do everything except push + PR; print what would happen
#   SESSION_LOG_MODEL=...     Gemini model (default: gemini-3.6-flash)
#   SESSION_LOG_NOTES_REPO    override notes repo (default: ~/work/notes)
#   SESSION_LOG_WORK_ROOT     override work root (default: ~/work)
#   SESSION_LOG_ENV           env file providing GEMINI_API_KEY (default: ~/work/dotfiles/.env)
#   SESSION_LOG_PRICE_IN      $/1M input tokens for the cost audit (default: 0.10)
#   SESSION_LOG_PRICE_OUT     $/1M output tokens for the cost audit (default: 0.40)

# launchd starts jobs with a minimal PATH; append (not prepend) the dirs our
# tools live in so an inherited/overridden PATH still takes precedence — this
# keeps launchd working while letting tests inject stub binaries.
export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Load GEMINI_API_KEY (and friends) from the dotfiles .env, mirroring install.sh.
ENV_FILE="${SESSION_LOG_ENV:-$HOME/work/dotfiles/.env}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

NOTES_REPO="${SESSION_LOG_NOTES_REPO:-$HOME/work/notes}"
WORK_ROOT="${SESSION_LOG_WORK_ROOT:-$HOME/work}"
WEEKLY_SUBPATH="NUS-Enterprise/Weekly"
PROJECTS_DIR="$HOME/.claude/projects"
WATERMARK="$HOME/.claude/.daily-session-log.watermark"
LOCKDIR="$HOME/.claude/.daily-session-log.lock"
DRY_RUN="${SESSION_LOG_DRY_RUN:-0}"
GEMINI_MODEL="${SESSION_LOG_MODEL:-gemini-3.6-flash}"
TODAY="$(date +%Y-%m-%d)"

# Cost/usage audit trail — one JSONL line per API call, plus a run-summary line.
# Token counts come from the API's usageMetadata (hard facts); cost is derived
# from configurable per-1M rates so the log stays right as pricing shifts.
# Lives in the notes repo (colocated with the notes it audits), but is written
# directly — never through the git worktree — so it doesn't disturb the checkout.
COST_LOG="${SESSION_LOG_COST_LOG:-$NOTES_REPO/logs/session-log-costs.jsonl}"
PRICE_IN="${SESSION_LOG_PRICE_IN:-0.10}"
PRICE_OUT="${SESSION_LOG_PRICE_OUT:-0.40}"
if [ "$DRY_RUN" = "1" ]; then DRY_JSON=true; else DRY_JSON=false; fi

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
audit() { mkdir -p "$(dirname "$COST_LOG")"; printf '%s\n' "$1" >> "$COST_LOG"; }
calc_cost() { awk -v i="$1" -v o="$2" -v pi="$PRICE_IN" -v po="$PRICE_OUT" \
  'BEGIN{printf "%.6f", i/1e6*pi + o/1e6*po}'; }

# --- preconditions -----------------------------------------------------------
for bin in curl jq git gh; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin not found on PATH"
done
[ -n "${GEMINI_API_KEY:-}" ] || die "GEMINI_API_KEY not set (add it to $ENV_FILE)"
[ -d "$NOTES_REPO/.git" ] || die "notes repo not a git checkout: $NOTES_REPO"
[ -d "$PROJECTS_DIR" ] || { log "no projects dir; nothing to do"; exit 0; }

# Single-instance guard (mkdir is atomic). Stale lock is caller's problem.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  log "another run holds the lock ($LOCKDIR); exiting"
  exit 0
fi
SCRATCH="$(mktemp -d)"
WORKTREE=""
cleanup() {
  # Remove the throwaway worktree and the local branch it created. The branch of
  # record lives on origin (real runs push it; same-day reruns key off
  # origin/<branch>), so the local ref is disposable — dropping it keeps the
  # user's notes repo from accumulating stray auto/session-log-* branches.
  if [ -n "$WORKTREE" ]; then
    git -C "$NOTES_REPO" worktree remove --force "$WORKTREE" 2>/dev/null || true
  fi
  if [ -n "${branch:-}" ]; then
    git -C "$NOTES_REPO" branch -D "$branch" 2>/dev/null || true
  fi
  rm -rf "$SCRATCH"
  rmdir "$LOCKDIR" 2>/dev/null || true
}
trap cleanup EXIT

RUN_START="$(date +%s)"

# --- which sessions? ("since last run" watermark) ---------------------------
# Encode ~/work the way Claude Code names project dirs: every "/" becomes "-".
# e.g. /Users/me/work -> -Users-me-work ; children are "<prefix>-<name>".
WORK_PREFIX="$(printf '%s' "$WORK_ROOT" | sed 's#/#-#g')"

# Build a reference file at the watermark time so BSD `find -newer` (portable,
# unlike GNU-only -newermt) can select sessions touched since the last run.
if [ -f "$WATERMARK" ]; then
  wm_epoch="$(cat "$WATERMARK")"
else
  # First run: look back 24h so we don't dump the entire history at once.
  wm_epoch="$(date -v-1d +%s 2>/dev/null || date -d '1 day ago' +%s)"
  log "no watermark; defaulting to last 24h"
fi
REF="$SCRATCH/watermark.ref"
touch -t "$(date -r "$wm_epoch" +%Y%m%d%H%M.%S)" "$REF"

# Project dirs under the work root (the root itself + all children).
# (while-read, not mapfile — macOS /bin/bash is 3.2 and has no mapfile.)
projdirs=()
while IFS= read -r d; do projdirs+=("$d"); done < <(find "$PROJECTS_DIR" -maxdepth 1 -type d \
  \( -name "$WORK_PREFIX" -o -name "${WORK_PREFIX}-*" \) 2>/dev/null | sort)
[ "${#projdirs[@]}" -gt 0 ] || { log "no ~/work project dirs; nothing to do"; exit 0; }

sessions=()
while IFS= read -r f; do sessions+=("$f"); done < <(find "${projdirs[@]}" -maxdepth 1 -name '*.jsonl' -newer "$REF" 2>/dev/null | sort)
if [ "${#sessions[@]}" -eq 0 ]; then
  log "no work sessions since last run; updating watermark and exiting"
  echo "$RUN_START" > "$WATERMARK"
  exit 0
fi
log "found ${#sessions[@]} work session(s) to log"

# --- summarize each session via the Gemini API -------------------------------
# Extract just the human/assistant text (drop thinking, tool calls, attachments),
# cap the size to bound tokens, and ask the model for bullets only.
CAP_BYTES=150000
SUMMARY_PROMPT='You are generating an employment work-log entry from ONE Claude Code session transcript.
Write terse, concrete markdown bullets of what was actually accomplished — files changed, decisions made, problems solved, commands that mattered.
Rules:
- Output ONLY markdown list items, each line starting with "- ". No headings, no preamble, no code fences, no closing text.
- Concrete over complete; reference artifacts by path. Skip filler and greetings.
- Redact any secrets, tokens, keys, or credentials.
- If nothing substantive was accomplished, output exactly: - (no substantive work)

Transcript follows:
---'

blocks=()           # one full markdown block per logged session
logged_labels=()    # for the commit/PR body
sum_in=0; sum_out=0; sum_total=0; calls_made=0   # cost-audit accumulators

for sf in "${sessions[@]}"; do
  sid="$(basename "$sf" .jsonl)"
  sid8="${sid:0:8}"

  # Label: prefer the session's AI title, else the working dir's basename.
  label="$(jq -rs 'map(select(.type=="ai-title") | .title) | last // empty' "$sf" 2>/dev/null)"
  if [ -z "$label" ]; then
    cwd="$(jq -rs 'map(select(.cwd) | .cwd) | last // empty' "$sf" 2>/dev/null)"
    label="$(basename "${cwd:-$sid8}")"
  fi

  transcript="$(jq -rs '
    map(
      select(.type=="user" or .type=="assistant")
      | .message as $m
      | ($m.role // "?") as $r
      | ($m.content) as $c
      | if ($c|type)=="string" then "\($r): \($c)"
        else ($c | map(select(.type=="text") | .text) | join("\n")) as $t
             | if ($t|length) > 0 then "\($r): \($t)" else empty end
        end
    ) | join("\n\n")
  ' "$sf" 2>/dev/null | head -c "$CAP_BYTES")"

  # Skip sessions with essentially no conversational content.
  if [ "${#transcript}" -lt 40 ]; then
    log "skip $sid8 ($label): too little content"
    continue
  fi

  log "summarizing $sid8 ($label)…"
  # jq builds the request so the prompt+transcript are safely JSON-escaped.
  # maxOutputTokens is generous because current Gemini flash models are "thinking"
  # models — internal reasoning draws from this same budget, so a tight cap
  # truncates the visible bullets on large sessions. Output tokens are cheap.
  req="$(jq -n --arg p "$SUMMARY_PROMPT" --arg tr "$transcript" \
    '{contents:[{parts:[{text: ($p + "\n" + $tr)}]}], generationConfig:{temperature:0.2, maxOutputTokens:2048}}')"
  resp="$(printf '%s' "$req" | curl -sS --max-time 120 -X POST \
    "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent" \
    -H "x-goog-api-key: ${GEMINI_API_KEY}" -H 'Content-Type: application/json' \
    -d @- 2>>"$SCRATCH/curl.err" || true)"
  raw="$(printf '%s' "$resp" | jq -r '.candidates[0].content.parts[]?.text // empty' 2>/dev/null)"
  err="$(printf '%s' "$resp" | jq -r '.error.message // empty' 2>/dev/null)"

  # Token usage for the audit (from usageMetadata; 0 when the call errored).
  u_in="$(printf '%s' "$resp" | jq -r '.usageMetadata.promptTokenCount // 0' 2>/dev/null)"; u_in="${u_in:-0}"
  u_total="$(printf '%s' "$resp" | jq -r '.usageMetadata.totalTokenCount // 0' 2>/dev/null)"; u_total="${u_total:-0}"
  u_out=$(( u_total > u_in ? u_total - u_in : 0 ))
  call_cost="$(calc_cost "$u_in" "$u_out")"

  # Keep only bullet lines; guards against any stray preamble the model emits.
  bullets="$(printf '%s\n' "$raw" | grep -E '^[[:space:]]*- ' || true)"
  loggable=false
  if [ -n "$raw" ] && [ -n "$bullets" ] && ! printf '%s' "$bullets" | grep -qiE '^\- \(no substantive work\)$'; then
    loggable=true
  fi

  # Record EVERY API call: one JSONL line with session id, tokens, and cost.
  audit "$(jq -nc --arg ts "$(now)" --arg session "$sid" --arg label "$label" \
    --arg model "$GEMINI_MODEL" --argjson in "$u_in" --argjson out "$u_out" --argjson total "$u_total" \
    --arg cost "$call_cost" --argjson logged "$loggable" --argjson dry "$DRY_JSON" --arg error "$err" \
    '{ts:$ts, type:"call", session:$session, label:$label, model:$model,
      input_tokens:$in, output_tokens:$out, total_tokens:$total,
      est_cost_usd:($cost|tonumber), logged:$logged, dry_run:$dry}
     + (if $error == "" then {} else {error:$error} end)')"
  calls_made=$((calls_made + 1))
  sum_in=$((sum_in + u_in)); sum_out=$((sum_out + u_out)); sum_total=$((sum_total + u_total))

  if [ -z "$raw" ]; then
    log "skip $sid8 ($label): Gemini returned no text${err:+ — $err}"
    continue
  fi
  if [ "$loggable" != true ]; then
    log "skip $sid8 ($label): no loggable work"
    continue
  fi

  # HTML comment carries the session id + date for same-day dedup (invisible in render).
  blocks+=("## Session log — ${TODAY} ${label}
<!-- auto-session-log ${sid} ${TODAY} -->

${bullets}")
  logged_labels+=("$label ($sid8)")
done

# Run-summary audit line (only when the run actually called the API).
if [ "$calls_made" -gt 0 ]; then
  run_cost="$(calc_cost "$sum_in" "$sum_out")"
  audit "$(jq -nc --arg ts "$(now)" --arg model "$GEMINI_MODEL" \
    --argjson calls "$calls_made" --argjson logged "${#blocks[@]}" \
    --argjson in "$sum_in" --argjson out "$sum_out" --argjson total "$sum_total" \
    --arg pin "$PRICE_IN" --arg pout "$PRICE_OUT" --arg cost "$run_cost" --argjson dry "$DRY_JSON" \
    '{ts:$ts, type:"run", model:$model, api_calls:$calls, sessions_logged:$logged,
      input_tokens:$in, output_tokens:$out, total_tokens:$total,
      price_per_M_in:($pin|tonumber), price_per_M_out:($pout|tonumber),
      est_cost_usd:($cost|tonumber), dry_run:$dry}')"
  log "cost: ~\$$run_cost ($sum_in in + $sum_out out tok over $calls_made call(s)) → $COST_LOG"
fi

if [ "${#blocks[@]}" -eq 0 ]; then
  log "nothing loggable across sessions; updating watermark and exiting"
  echo "$RUN_START" > "$WATERMARK"
  exit 0
fi

# --- git worktree: apply, commit, push, PR — never touch the real checkout ---
base="$(git -C "$NOTES_REPO" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's#.*/##')"
base="${base:-main}"
branch="auto/session-log-${TODAY}"
git -C "$NOTES_REPO" fetch --quiet origin "$base" || die "git fetch failed"
WORKTREE="$SCRATCH/wt"

# Reuse today's branch if it already exists on origin (idempotent same-day reruns),
# otherwise start it from the base branch.
if git -C "$NOTES_REPO" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
  git -C "$NOTES_REPO" worktree add --quiet -B "$branch" "$WORKTREE" "origin/$branch"
else
  git -C "$NOTES_REPO" worktree add --quiet -B "$branch" "$WORKTREE" "origin/$base"
fi

# Resolve the target weekly note INSIDE the worktree (same rule as /done).
weekly_dir="$WORKTREE/$WEEKLY_SUBPATH"
[ -d "$weekly_dir" ] || die "weekly dir missing in repo: $WEEKLY_SUBPATH"
week="$(ls "$weekly_dir"/[0-9]*-W[0-9]*.md 2>/dev/null \
  | sed -E 's|.*/([0-9]{4}-W[0-9]{2}).*|\1|' | sort -u | tail -1)"
[ -n "$week" ] || die "no ISO-week notes found in $WEEKLY_SUBPATH"
target="$weekly_dir/$week.md"       # base note for the week, not a -N variant
[ -f "$target" ] || : > "$target"   # create base if only variants exist

# Append each block, skipping any whose (session,date) marker is already present
# (idempotent same-day reruns).
for block in "${blocks[@]}"; do
  sid="$(printf '%s\n' "$block" | awk '/^<!-- auto-session-log/{print $3; exit}')"
  if grep -qF "auto-session-log ${sid} ${TODAY}" "$target"; then
    log "skip ${sid:0:8}: already logged today"
    continue
  fi
  printf '\n%s\n' "$block" >> "$target"
done

# Recompute whether anything actually changed (all blocks may have been dupes).
if git -C "$WORKTREE" diff --quiet -- "$WEEKLY_SUBPATH/$week.md"; then
  log "all entries already logged today; nothing to commit"
  echo "$RUN_START" > "$WATERMARK"
  exit 0
fi

rel="$WEEKLY_SUBPATH/$week.md"
body="Automated session log for ${TODAY}.\n\nSessions:\n"
for l in "${logged_labels[@]}"; do body+="- $l\n"; done

if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN — diff that would be committed:"
  git -C "$WORKTREE" --no-pager diff -- "$rel" || true
  log "DRY RUN — would push branch '$branch' and open PR against '$base'"
  echo "$RUN_START" > "$WATERMARK"
  exit 0
fi

git -C "$WORKTREE" add "$rel"
git -C "$WORKTREE" commit --quiet -m "chore(weekly): auto session log ${TODAY}"
git -C "$WORKTREE" push --quiet -u origin "$branch"

# Open a PR only if one isn't already open for this branch.
if gh pr view "$branch" --repo "$(git -C "$NOTES_REPO" remote get-url origin)" >/dev/null 2>&1; then
  log "PR already open for $branch; pushed new commit"
else
  ( cd "$WORKTREE" && printf '%b' "$body" \
      | gh pr create --base "$base" --head "$branch" \
          --title "Session log — ${TODAY}" --body-file - )
  log "opened PR for $branch"
fi

echo "$RUN_START" > "$WATERMARK"
log "done: logged ${#logged_labels[@]} session(s) to $rel"
