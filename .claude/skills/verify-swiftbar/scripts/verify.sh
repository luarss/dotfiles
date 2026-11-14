#!/usr/bin/env bash
set -euo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export PATH="$PATH:/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES="$(cd "$SKILL_DIR/../../.." && pwd)"
PLUGIN="${PRODWATCH_PLUGIN:-$DOTFILES/.config/swiftbar/prodwatch.60s.sh}"
INSTALLED_PLUGIN="$HOME/.config/swiftbar/prodwatch.60s.sh"
REAL_CACHE="$HOME/.cache/prodwatch"
SANDBOX_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)/verify-swiftbar"
EVIDENCE_BASE="${VERIFY_SWIFTBAR_EVIDENCE_DIR:-$HOME/.cache/verify-swiftbar}"
MARKER=".verify-swiftbar-sandbox"
ALLOWED_PARAMS="font size color href refresh"

usage() {
  cat <<EOF
usage: verify.sh <command> <run-id> [args]

  doctor  <run-id>                        read-only health check (SwiftBar, install, deps, gh budget)
  run     <run-id> <label> [-- KEY=VAL..] run the real plugin with a sandboxed cache, capture + lint
  check   <run-id> <label>                compare a run's numbers against independent oracles
  live    <run-id> <label> [frames]       refresh the plugin inside SwiftBar and screenshot the display
  paths   <run-id>                        print sandbox and evidence paths
  cleanup <run-id>                        delete the sandbox (evidence is kept)
EOF
  exit 2
}

[ $# -ge 2 ] || usage
COMMAND="$1"
RUN_ID="$2"
shift 2
case "$RUN_ID" in
  *[!A-Za-z0-9._-]*|"") echo "run-id must match [A-Za-z0-9._-]+" >&2; exit 2 ;;
esac

SANDBOX="$SANDBOX_BASE/$RUN_ID"
SANDBOX_CACHE="$SANDBOX/cache"
EVIDENCE="$EVIDENCE_BASE/$RUN_ID"

iso_with_colon() {
  date "+$1%z" | sed 's/\(..\)$/:\1/'
}

ensure_sandbox() {
  mkdir -p "$SANDBOX_CACHE"
  touch "$SANDBOX/$MARKER"
}

new_label_dir() {
  local label="$1"
  case "$label" in
    *[!A-Za-z0-9._-]*|"") echo "label must match [A-Za-z0-9._-]+" >&2; exit 2 ;;
  esac
  if [ -e "$EVIDENCE/$label" ]; then
    echo "label already used: $EVIDENCE/$label" >&2
    exit 1
  fi
  mkdir -p "$EVIDENCE/$label"
}

snapshot_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f -exec stat -f '%N %z %m' {} \; | sort
  else
    echo "(absent) $dir"
  fi
}

lint_output() {
  local stdout_file="$1" in_title=1 titles=0 line_number=0 problems=0 line text params param key
  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    if [ "$line" = "---" ]; then
      in_title=0
      continue
    fi
    [ "$in_title" -eq 1 ] && titles=$((titles + 1))
    case "$line" in
      *" | "*) ;;
      *) echo "FAIL line $line_number has no ' | ' params: $line"; problems=$((problems + 1)); continue ;;
    esac
    text="${line%% | *}"
    params="${line#* | }"
    [ -n "${text// /}" ] || { echo "FAIL line $line_number has empty text"; problems=$((problems + 1)); }
    for param in $params; do
      key="${param%%=*}"
      if [ "$key" = "$param" ] || [[ " $ALLOWED_PARAMS " != *" $key "* ]]; then
        echo "FAIL line $line_number has unknown param '$param'"
        problems=$((problems + 1))
      fi
    done
    if [ "$in_title" -eq 1 ] && ! [[ "$text" =~ [0-9] ]]; then
      echo "FAIL title line $line_number shows no number: $text"
      problems=$((problems + 1))
    fi
  done < "$stdout_file"
  [ "$titles" -ge 1 ] || { echo "FAIL no title lines before the first ---"; problems=$((problems + 1)); }
  echo "titles=$titles problems=$problems"
  [ "$problems" -eq 0 ]
}

run_plugin() {
  local label="${1:-}"
  [ -n "$label" ] || usage
  shift
  [ "${1:-}" = "--" ] && shift
  local assignment
  for assignment in "$@"; do
    [[ "$assignment" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || { echo "expected KEY=VAL, got: $assignment" >&2; exit 2; }
  done
  ensure_sandbox
  new_label_dir "$label"
  local dir="$EVIDENCE/$label" started finished status=0
  printf '%q ' env PRODWATCH_CACHE_DIR="$SANDBOX_CACHE" "$@" bash "$PLUGIN" > "$dir/command.txt"
  echo >> "$dir/command.txt"
  snapshot_dir "$REAL_CACHE" > "$dir/real-cache-before.txt"
  snapshot_dir "$SANDBOX_CACHE" > "$dir/cache-before.txt"
  iso_with_colon '%Y-%m-%dT%H:%M:%S' > "$dir/ran-at.txt"
  started="$(date +%s)"
  env PRODWATCH_CACHE_DIR="$SANDBOX_CACHE" "$@" bash "$PLUGIN" > "$dir/stdout.txt" 2> "$dir/stderr.txt" || status=$?
  finished="$(date +%s)"
  echo "$status" > "$dir/exit-code.txt"
  echo "$((finished - started))" > "$dir/duration-seconds.txt"
  snapshot_dir "$REAL_CACHE" > "$dir/real-cache-after.txt"
  snapshot_dir "$SANDBOX_CACHE" > "$dir/cache-after.txt"
  diff "$dir/real-cache-before.txt" "$dir/real-cache-after.txt" > "$dir/real-cache.diff" || true
  diff "$dir/cache-before.txt" "$dir/cache-after.txt" > "$dir/cache.diff" || true
  mkdir -p "$dir/cache"
  cp "$SANDBOX_CACHE"/*.json "$dir/cache/" 2> /dev/null || true
  local lint_status=0
  lint_output "$dir/stdout.txt" > "$dir/lint.txt" || lint_status=$?
  cat "$dir/stdout.txt"
  echo "--- verify-swiftbar ---"
  echo "exit=$status duration=$(cat "$dir/duration-seconds.txt")s lint: $(tail -1 "$dir/lint.txt")"
  [ -s "$dir/real-cache.diff" ] && echo "WARN real ~/.cache/prodwatch changed during the run (SwiftBar's own refresh, or a leak: see real-cache.diff)"
  echo "evidence: $dir"
  [ "$status" -eq 0 ] && [ "$lint_status" -eq 0 ]
}

extract() {
  local stdout_file="$1" pattern="$2" replacement="$3"
  sed -nE "s/$pattern/$replacement/p" "$stdout_file" | head -1
}

plugin_values() {
  local out="$1" title
  title="$(head -1 "$out")"
  printf 'contributions\t%s\n' "$(sed -nE 's/^<> ([0-9]+).*/\1/p' <<<"$title")"
  printf 'prs\t%s\n' "$(sed -nE 's/^<> [0-9]+ · PR ([0-9]+) \|.*/\1/p' <<<"$title")"
  printf 'issues_opened\t%s\n' "$(extract "$out" '^Issues today · ↑([0-9]+) opened · ↓[0-9]+ closed \|.*' '\1')"
  printf 'issues_closed\t%s\n' "$(extract "$out" '^Issues today · ↑[0-9]+ opened · ↓([0-9]+) closed \|.*' '\1')"
  printf 'cost_total\t%s\n' "$(extract "$out" '^\$([0-9.]+) · .*' '\1')"
  printf 'work_commits\t%s\n' "$(extract "$out" '^Work today · ([0-9]+) commits .*' '\1')"
  printf 'work_lines\t%s\n' "$(extract "$out" '^Work today · [0-9]+ commits · (\+[0-9]+\/-[0-9]+) \|.*' '\1')"
  printf 'projects_commits\t%s\n' "$(extract "$out" '^Projects today · ([0-9]+) commits .*' '\1')"
  printf 'projects_lines\t%s\n' "$(extract "$out" '^Projects today · [0-9]+ commits · (\+[0-9]+\/-[0-9]+) \|.*' '\1')"
  printf 'disk_free_percent\t%s\n' "$(extract "$out" '^Disk · .* free \(([0-9]+)%\) \|.*' '\1')"
  printf 'temp_avg\t%s\n' "$(extract "$out" '^SoC temp · avg ([0-9]+)°C .*' '\1')"
}

oracle_git() {
  local base="$1" author="$2" since="$3" dir commits=0 added=0 deleted=0 counts
  for dir in "$base"/*/; do
    [ -d "$dir/.git" ] || continue
    counts="$(git -C "$dir" log --since="$since" --author="$author" --format='tformat:COMMIT' --shortstat 2> /dev/null \
      | awk '/^COMMIT$/{c++} /changed/{for(i=1;i<=NF;i++){if($(i)~/^insertion/)a+=$(i-1); if($(i)~/^deletion/)d+=$(i-1)}} END{print c+0, a+0, d+0}')"
    read -r c a d <<<"$counts"
    commits=$((commits + c)); added=$((added + a)); deleted=$((deleted + d))
  done
  echo "$commits +$added/-$deleted"
}

oracle_values() {
  local midnight now today since identity_file work_author projects_author
  midnight="$(iso_with_colon '%Y-%m-%dT00:00:00')"
  now="$(iso_with_colon '%Y-%m-%dT%H:%M:%S')"
  today="$(date +%Y-%m-%d)"
  since="$(date +%Y-%m-%dT00:00:00)"
  identity_file="${PRODWATCH_IDENTITY_FILE:-$HOME/.config/prodwatch/identity}"
  [ -f "$identity_file" ] && . "$identity_file"
  work_author="${PRODWATCH_WORK_AUTHOR:-song.luar@a5x.ai}"
  projects_author="${PRODWATCH_PROJ_AUTHOR:-song.luar@a5x.ai\|luarss@users.noreply.github.com}"

  local calendar_query='query($from: DateTime!, $to: DateTime!){viewer{contributionsCollection(from:$from,to:$to){contributionCalendar{weeks{contributionDays{date contributionCount}}}}}}'
  printf 'contributions\t%s\n' "$(gh api graphql -f query="$calendar_query" -f from="$midnight" -f to="$now" 2> /dev/null \
    | jq -r --arg today "$today" '[.data.viewer.contributionsCollection.contributionCalendar.weeks[].contributionDays[] | select(.date == $today) | .contributionCount] | add // empty')"
  printf 'prs\t%s\n' "$(gh search prs --author=@me --created=">=$midnight" --limit 1000 --json url 2> /dev/null | jq -r 'length')"
  printf 'issues_opened\t%s\n' "$( { gh search issues --author=@me --created=">=$midnight" --limit 1000 --json url 2> /dev/null
      gh search issues --assignee=@me --created=">=$midnight" --limit 1000 --json url 2> /dev/null; } | jq -rs 'add | map(.url) | unique | length')"
  printf 'issues_closed\t%s\n' "$( { gh search issues --author=@me --closed=">=$midnight" --limit 1000 --json url 2> /dev/null
      gh search issues --assignee=@me --closed=">=$midnight" --limit 1000 --json url 2> /dev/null; } | jq -rs 'add | map(.url) | unique | length')"
  printf 'cost_total\t%s\n' "$(ccusage daily --json --since "$(date +%Y%m%d)" 2> /dev/null | jq -r '.daily[-1].totalCost // 0 | . * 100 | round / 100')"
  local work projects
  work="$(oracle_git "$HOME/work" "$work_author" "$since")"
  projects="$(oracle_git "$HOME/projects" "$projects_author" "$since")"
  printf 'work_commits\t%s\n' "${work%% *}"
  printf 'work_lines\t%s\n' "${work#* }"
  printf 'projects_commits\t%s\n' "${projects%% *}"
  printf 'projects_lines\t%s\n' "${projects#* }"
  printf 'disk_free_percent\t%s\n' "$(df -k /System/Volumes/Data 2> /dev/null | awk 'NR==2{gsub("%","",$5); print 100-$5}')"
  printf 'temp_avg\t20..110\n'
}

classify() {
  local key="$1" shown="$2" expected="$3"
  if [ -z "$shown" ] && [ -z "$expected" ]; then echo "SKIP"; return; fi
  if [ -z "$expected" ]; then echo "NO_ORACLE"; return; fi
  if [ -z "$shown" ]; then echo "MISSING"; return; fi
  case "$key" in
    temp_avg)
      [ "$shown" -ge 20 ] && [ "$shown" -le 110 ] && echo "SANE" || echo "MISMATCH" ;;
    disk_free_percent)
      local gap=$((shown - expected)); gap=${gap#-}
      [ "$gap" -le 1 ] && echo "MATCH" || echo "MISMATCH" ;;
    cost_total)
      awk -v s="$shown" -v e="$expected" 'BEGIN{
        if (s == e) print "MATCH";
        else if (e > s && e - s <= (e * 0.05 > 0.5 ? e * 0.05 : 0.5)) print "DRIFT";
        else print "MISMATCH" }' ;;
    work_lines|projects_lines)
      [ "$shown" = "$expected" ] && echo "MATCH" || echo "DRIFT?" ;;
    *)
      awk -v s="$shown" -v e="$expected" 'BEGIN{
        if (s == e) print "MATCH";
        else if (e > s && e - s <= (e * 0.05 > 2 ? e * 0.05 : 2)) print "DRIFT";
        else print "MISMATCH" }' ;;
  esac
}

check_run() {
  local label="${1:-}"
  [ -n "$label" ] || usage
  local dir="$EVIDENCE/$label"
  [ -s "$dir/stdout.txt" ] || { echo "no stdout for $dir (run it first)" >&2; exit 1; }
  plugin_values "$dir/stdout.txt" > "$dir/shown.tsv"
  oracle_values > "$dir/expected.tsv"
  iso_with_colon '%Y-%m-%dT%H:%M:%S' > "$dir/checked-at.txt"
  local key shown expected verdict mismatches=0
  {
    printf '%-18s %-14s %-14s %s\n' FIELD SHOWN ORACLE VERDICT
    while IFS=$'\t' read -r key shown; do
      expected="$(awk -F'\t' -v k="$key" '$1==k{print $2}' "$dir/expected.tsv")"
      verdict="$(classify "$key" "$shown" "$expected")"
      case "$verdict" in MISMATCH|MISSING) mismatches=$((mismatches + 1)) ;; esac
      printf '%-18s %-14s %-14s %s\n' "$key" "${shown:--}" "${expected:--}" "$verdict"
    done < "$dir/shown.tsv"
    echo "mismatches=$mismatches ran-at=$(cat "$dir/ran-at.txt") checked-at=$(cat "$dir/checked-at.txt")"
  } | tee "$dir/verdict.txt"
  [ "$mismatches" -eq 0 ]
}

live_refresh() {
  local label="${1:-}" frames="${2:-4}" frame
  [ -n "$label" ] || usage
  pgrep -x SwiftBar > /dev/null || { echo "SwiftBar is not running" >&2; exit 1; }
  ensure_sandbox
  new_label_dir "$label"
  local dir="$EVIDENCE/$label"
  snapshot_dir "$REAL_CACHE" > "$dir/real-cache-before.txt"
  open -g "swiftbar://refreshplugin?name=prodwatch"
  echo "swiftbar://refreshplugin?name=prodwatch" > "$dir/command.txt"
  sleep 3
  for frame in $(seq 1 "$frames"); do
    screencapture -x -m "$dir/screen-$frame.png"
    [ "$frame" -lt "$frames" ] && sleep 5
  done
  local width
  width="$(sips -g pixelWidth "$dir/screen-1.png" 2> /dev/null | awk '/pixelWidth/{print $2}')"
  for frame in $(seq 1 "$frames"); do
    [ -n "$width" ] && sips -c 80 "$width" --cropOffset 0 0 "$dir/screen-$frame.png" --out "$dir/menubar-$frame.png" > /dev/null 2>&1 || true
  done
  snapshot_dir "$REAL_CACHE" > "$dir/real-cache-after.txt"
  diff "$dir/real-cache-before.txt" "$dir/real-cache-after.txt" > "$dir/real-cache.diff" || true
  bash "$INSTALLED_PLUGIN" > "$dir/stdout.txt" 2> "$dir/stderr.txt" || true
  sed '/^---$/q' "$dir/stdout.txt" | sed '$d' > "$dir/expected-titles.txt"
  echo "frames: $dir/menubar-*.png"
  echo "expected title lines (one per ~5s rotation):"
  cat "$dir/expected-titles.txt"
}

doctor() {
  local failures=0
  pass() { echo "PASS $*"; }
  fail() { echo "FAIL $*"; failures=$((failures + 1)); }
  warn() { echo "WARN $*"; }
  [ "$(uname -s)" = "Darwin" ] && pass "macOS" || fail "not macOS"
  pgrep -x SwiftBar > /dev/null && pass "SwiftBar running" || warn "SwiftBar not running (run/check still work; live does not)"
  local plugin_dir
  plugin_dir="$(defaults read com.ameba.SwiftBar PluginDirectory 2> /dev/null || true)"
  [ "$plugin_dir" = "$HOME/.config/swiftbar" ] && pass "SwiftBar PluginDirectory=$plugin_dir" || warn "SwiftBar PluginDirectory='$plugin_dir'"
  if [ "$(readlink "$INSTALLED_PLUGIN" 2> /dev/null)" = "$DOTFILES/.config/swiftbar/prodwatch.60s.sh" ]; then
    pass "installed plugin symlinks to this repo"
  else
    warn "installed plugin is not a symlink to $DOTFILES (live shows a different file than run)"
  fi
  [ -x "$PLUGIN" ] && pass "plugin executable: $PLUGIN" || fail "plugin not executable: $PLUGIN"
  bash -n "$PLUGIN" && pass "plugin parses (bash -n)" || fail "plugin has a syntax error"
  local tool
  for tool in git jq node python3 ccusage gh; do
    command -v "$tool" > /dev/null && pass "$tool: $(command -v "$tool")" || fail "$tool missing"
  done
  if gh auth status > /dev/null 2>&1; then
    pass "gh authenticated"
    local budget
    budget="$(gh api rate_limit --jq '.resources.graphql | "\(.remaining)/\(.limit)"' 2> /dev/null || true)"
    [ -n "$budget" ] && pass "gh graphql budget $budget" || warn "could not read gh rate limit"
  else
    fail "gh not authenticated (gh auth login)"
  fi
  local identity_file="${PRODWATCH_IDENTITY_FILE:-$HOME/.config/prodwatch/identity}"
  [ -f "$identity_file" ] && pass "identity file: $identity_file" || pass "no identity file (luarss defaults)"
  case "$SANDBOX" in
    "$REAL_CACHE"*) fail "sandbox overlaps the real cache" ;;
    *) pass "sandbox cache: $SANDBOX_CACHE" ;;
  esac
  echo "evidence: $EVIDENCE"
  [ "$failures" -eq 0 ]
}

cleanup() {
  case "$SANDBOX" in
    "$SANDBOX_BASE"/?*) ;;
    *) echo "refusing to delete unexpected path: $SANDBOX" >&2; exit 1 ;;
  esac
  if [ ! -e "$SANDBOX" ]; then
    echo "nothing to clean: $SANDBOX"
  elif [ -f "$SANDBOX/$MARKER" ]; then
    rm -rf "$SANDBOX"
    echo "removed sandbox: $SANDBOX"
  else
    echo "refusing to delete $SANDBOX: no sandbox marker" >&2
    exit 1
  fi
  [ -d "$EVIDENCE" ] && echo "evidence kept: $EVIDENCE"
  return 0
}

case "$COMMAND" in
  doctor) doctor ;;
  run) run_plugin "$@" ;;
  check) check_run "$@" ;;
  live) live_refresh "$@" ;;
  paths) printf 'sandbox=%s\ncache=%s\nevidence=%s\n' "$SANDBOX" "$SANDBOX_CACHE" "$EVIDENCE" ;;
  cleanup) cleanup ;;
  *) usage ;;
esac
