#!/bin/bash
# SwiftBar productivity widget: today's git activity + Claude/Antigravity usage.
# Refreshes every 60s (filename ".60s."). Deliberately lightweight: one git
# pass per repo, one jq call, active repos only.
export PATH="$PATH:/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin"

PARSE_USAGE_JQ='
def fmt2:
  ((. // 0 | tonumber) * 100 | round) as $n
  | (if $n < 0 then "-" else "" end) as $sign
  | (($n | fabs) | tostring) as $s
  | $sign + if ($s | length) == 1 then "0.0" + $s
            elif ($s | length) == 2 then "0." + $s
            else $s[:-2] + "." + $s[-2:] end;
def fmtTok:
  (. // 0 | tonumber) as $n
  | if $n >= 1000000 then
      (($n / 100000 | round | tostring) as $s | $s[:-1] + "." + $s[-1:] + "M")
    elif $n >= 1000 then
      (($n / 1000 | round | tostring) + "k")
    else ($n | tostring) end;
def cleanModels:
  [(. // [])[]
    | sub("^(claude|gemini)-"; "")
    | sub("-[0-9]{8}$"; "")
    | select(length > 0)]
  | reduce .[] as $m ([]; if index($m) then . else . + [$m] end)
  | if length == 0 then "-" else join(",") end;
((.daily // [])[-1]) as $t
| if $t == null then ["0.00", "0", "0.00", "0", "-", "0.00", "0", "-"]
  else
    ($t.agents | if type == "array" then . else [] end) as $agents
    | ($agents | map(select((.agent // "" | ascii_downcase) == "claude")) | .[0]) as $c0
    | ($agents | map(select((.agent // "" | ascii_downcase) == "antigravity")) | .[0]) as $a0
    | (if $c0 == null and $a0 == null and ($t.metadata.agents? | type == "array") then
         if ($t.metadata.agents | index("claude")) and ($t.metadata.agents | index("antigravity") | not)
         then $t else null end
       else $c0 end) as $c
    | (if $c0 == null and $a0 == null and ($t.metadata.agents? | type == "array") then
         if ($t.metadata.agents | index("antigravity")) and ($t.metadata.agents | index("claude") | not)
         then $t else null end
       else $a0 end) as $a
    | [($t.totalCost | fmt2), ($t.totalTokens | fmtTok),
       ($c.totalCost | fmt2), ($c.totalTokens | fmtTok), ($c.modelsUsed | cleanModels),
       ($a.totalCost | fmt2), ($a.totalTokens | fmtTok), ($a.modelsUsed | cleanModels)]
  end
| @tsv'

if [ "${1:-}" = "--parse-usage" ]; then
  parsed="$(jq -r "$PARSE_USAGE_JQ" 2>/dev/null)" || parsed=""
  if [ -n "$parsed" ]; then
    printf '%s\n' "$parsed"
  else
    printf '0.00\t0\t0.00\t0\t-\t0.00\t0\t-\n'
  fi
  exit 0
fi

read -r TODAY_DASH TODAY_COMPACT NOW_TIME NOW_HM NOW_TZ NOW_EPOCH < <(date '+%Y-%m-%d %Y%m%d %H:%M:%S %H:%M %z %s')

WORK="$HOME/work"
PROJECTS="$HOME/projects"
SINCE="${TODAY_DASH}T00:00:00"
IDENTITY_FILE="${PRODWATCH_IDENTITY_FILE:-$HOME/.config/prodwatch/identity}"
[ -f "$IDENTITY_FILE" ] && . "$IDENTITY_FILE"
# --author is a regex; \| alternation lets one scan match several identities.
WORK_AUTHOR="${PRODWATCH_WORK_AUTHOR:-song.luar@a5x.ai}"
# ~/projects repos commit under the personal GitHub noreply identity too.
PROJ_AUTHOR="${PRODWATCH_PROJ_AUTHOR:-song.luar@a5x.ai\|luarss@users.noreply.github.com}"
GITHUB_USER="${PRODWATCH_GITHUB_USER:-luarss}"

CACHE_DIR="${PRODWATCH_CACHE_DIR:-$HOME/.cache/prodwatch}"
CCUSAGE_TTL="${PRODWATCH_CCUSAGE_TTL:-600}"
USAGE_CACHE="$CACHE_DIR/ccusage-${TODAY_COMPACT}.json"
USAGE_LOCK="$CACHE_DIR/ccusage.lock"
USAGE_WAIT="${PRODWATCH_USAGE_WAIT:-20}"
USAGE_POLL="${PRODWATCH_USAGE_POLL:-0.2}"
USAGE_LOCK_STALE="${PRODWATCH_USAGE_LOCK_STALE:-900}"
EXTRA_CLAUDE_DIRS="${PRODWATCH_EXTRA_CLAUDE_DIRS:-$HOME/.claude-alt-profile}"

cache_age_seconds() {
  local modified
  if [[ "$OSTYPE" == darwin* ]]; then
    modified="$(stat -f %m "$1" 2>/dev/null)" || return 1
  else
    modified="$(stat -c %Y "$1" 2>/dev/null)" || return 1
  fi
  echo $(( NOW_EPOCH - modified ))
}

usage_cache_is_fresh() {
  local age
  [ -s "$USAGE_CACHE" ] || return 1
  age="$(cache_age_seconds "$USAGE_CACHE")" || return 1
  [ "$age" -lt "$CCUSAGE_TTL" ]
}

usage_is_fully_priced() {
  jq -e '[.daily[]?.agents[]?.modelBreakdowns[]?
          | select((.modelName // "") | startswith("model_placeholder_") | not)
          | select((.inputTokens + .outputTokens + .cacheCreationTokens + .cacheReadTokens) > 0 and .cost == 0)]
         | length == 0' "$1" >/dev/null 2>&1
}

MERGE_CLAUDE_USAGE='
def add_usage($extra):
  reduce ("inputTokens", "outputTokens", "cacheCreationTokens", "cacheReadTokens", "totalTokens", "totalCost") as $field
    (.; .[$field] = ((.[$field] // 0) + ($extra[$field] // 0)))
  | .modelsUsed = ((.modelsUsed // []) + ($extra.modelsUsed // []) | unique)
  | .modelBreakdowns = ((.modelBreakdowns // []) + ($extra.modelBreakdowns // []));
def add_claude_agent($extra):
  if any(.agents[]?; .agent == "claude")
  then .agents |= map(if .agent == "claude" then add_usage($extra) else . end)
  else .agents = ((.agents // []) + [$extra + {agent: "claude"}])
  end;
($extra[0].daily // [])[-1] as $today
| if $today == null then .
  elif (.daily // []) == [] then .daily = [{agent: "all", agents: []} | add_usage($today) | add_claude_agent($today)]
  else .daily[-1] |= (add_usage($today) | add_claude_agent($today))
  end'

merge_extra_claude_usage() {
  local report="$1" config_dir extra merged extra_dirs
  IFS=',' read -ra extra_dirs <<<"$EXTRA_CLAUDE_DIRS"
  for config_dir in "${extra_dirs[@]}"; do
    [ -d "$config_dir/projects" ] || continue
    extra="$(mktemp "$CACHE_DIR/ccusage-extra.XXXXXX")"
    merged="$(mktemp "$CACHE_DIR/ccusage-merged.XXXXXX")"
    if ! CLAUDE_CONFIG_DIR="$config_dir" ccusage claude daily --json --since "$TODAY_COMPACT" >"$extra" 2>/dev/null \
      || ! jq --slurpfile extra "$extra" "$MERGE_CLAUDE_USAGE" "$report" >"$merged" 2>/dev/null; then
      rm -f "$extra" "$merged"
      return 1
    fi
    mv -f "$merged" "$report"
    rm -f "$extra"
  done
}

refresh_usage_cache() {
  local fresh f
  mkdir -p "$CACHE_DIR"
  fresh="$(mktemp "$CACHE_DIR/ccusage.XXXXXX")"
  if ccusage daily --json --by-agent --since "$TODAY_COMPACT" >"$fresh" 2>/dev/null && [ -s "$fresh" ] \
    && merge_extra_claude_usage "$fresh" && usage_is_fully_priced "$fresh"; then
    mv -f "$fresh" "$USAGE_CACHE"
    for f in "$CACHE_DIR"/ccusage-*.json; do
      [ "$f" = "$USAGE_CACHE" ] || rm -f "$f"
    done
  else
    rm -f "$fresh"
  fi
}

acquire_usage_lock() {
  local age
  mkdir -p "$CACHE_DIR"
  if [ -d "$USAGE_LOCK" ]; then
    age="$(cache_age_seconds "$USAGE_LOCK")" || age=0
    [ "$age" -ge "$USAGE_LOCK_STALE" ] && rmdir "$USAGE_LOCK" 2>/dev/null
  fi
  mkdir "$USAGE_LOCK" 2>/dev/null
}

release_usage_lock() {
  rm -f "$CACHE_DIR"/ccusage.?????? "$CACHE_DIR"/ccusage-extra.?????? "$CACHE_DIR"/ccusage-merged.??????
  rmdir "$USAGE_LOCK" 2>/dev/null
}

if [ "${1:-}" = "--refresh-usage-cache" ]; then
  trap release_usage_lock EXIT
  refresh_usage_cache
  exit 0
fi

start_detached_usage_refresh() {
  acquire_usage_lock || return 0
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' bash "${BASH_SOURCE[0]}" --refresh-usage-cache \
    </dev/null >/dev/null 2>&1 &
}

wait_for_usage_refresh() {
  local deadline=$((SECONDS + USAGE_WAIT))
  while [ -d "$USAGE_LOCK" ] && [ "$SECONDS" -lt "$deadline" ]; do
    sleep "$USAGE_POLL"
  done
}

# ccusage can outlast a 60s refresh, so it runs in its own session where
# SwiftBar killing this run can't take it down; we wait briefly, then render
# whatever cache exists.
USAGE_PID=""
if ! usage_cache_is_fresh; then
  (
    start_detached_usage_refresh
    wait_for_usage_refresh
  ) &
  USAGE_PID=$!
fi

GH_CACHE="$CACHE_DIR/github-${TODAY_COMPACT}.json"
GH_TTL="${PRODWATCH_GH_TTL:-300}"
GH_MIN_REMAINING="${PRODWATCH_GH_MIN_REMAINING:-500}"
GITHUB_QUERY='
query($from: DateTime!, $to: DateTime!, $prsOpened: String!, $authorOpened: String!, $assigneeOpened: String!,
      $authorClosed: String!, $assigneeClosed: String!) {
  viewer {
    contributionsCollection(from: $from, to: $to) {
      contributionCalendar { weeks { contributionDays { date contributionCount } } }
    }
  }
  prsOpened: search(query: $prsOpened, type: ISSUE) { issueCount }
  authorOpened: search(query: $authorOpened, type: ISSUE, first: 100) { nodes { ... on Issue { url } } }
  assigneeOpened: search(query: $assigneeOpened, type: ISSUE, first: 100) { nodes { ... on Issue { url } } }
  authorClosed: search(query: $authorClosed, type: ISSUE, first: 100) { nodes { ... on Issue { url } } }
  assigneeClosed: search(query: $assigneeClosed, type: ISSUE, first: 100) { nodes { ... on Issue { url } } }
  rateLimit { remaining resetAt }
}'

github_cache_is_fresh() {
  local age
  [ -s "$GH_CACHE" ] || return 1
  age="$(cache_age_seconds "$GH_CACHE")" || return 1
  [ "$age" -lt "$GH_TTL" ]
}

github_budget_is_low() {
  [ -s "$GH_CACHE" ] || return 1
  jq -e --argjson floor "$GH_MIN_REMAINING" \
    '.data.rateLimit | .remaining < $floor and (.resetAt | fromdateiso8601) > now' \
    "$GH_CACHE" >/dev/null 2>&1
}

refresh_github_cache() {
  local out fresh tz_iso midnight now f
  command -v gh >/dev/null 2>&1 || return
  tz_iso="${NOW_TZ%??}:${NOW_TZ#???}"
  midnight="${TODAY_DASH}T00:00:00${tz_iso}"
  now="${TODAY_DASH}T${NOW_TIME}${tz_iso}"
  out="$(gh api graphql -f query="$GITHUB_QUERY" -f from="$midnight" -f to="$now" \
      -f prsOpened="is:pr author:@me created:>=$midnight" \
      -f authorOpened="is:issue author:@me created:>=$midnight" \
      -f assigneeOpened="is:issue assignee:@me created:>=$midnight" \
      -f authorClosed="is:issue author:@me closed:>=$midnight" \
      -f assigneeClosed="is:issue assignee:@me closed:>=$midnight" 2>/dev/null)" || return
  [ -n "$out" ] || return
  jq -e '.data.viewer.contributionsCollection' <<<"$out" >/dev/null 2>&1 || return
  mkdir -p "$CACHE_DIR"
  fresh="$(mktemp "$CACHE_DIR/github.XXXXXX")"
  printf '%s\n' "$out" >"$fresh"
  mv -f "$fresh" "$GH_CACHE"
  for f in "$CACHE_DIR"/github-*.json; do
    [ "$f" = "$GH_CACHE" ] || rm -f "$f"
  done
}

GH_PID=""
if ! github_cache_is_fresh; then
  (
    github_budget_is_low || refresh_github_cache
  ) &
  GH_PID=$!
fi

TEMP_RAW="$(mktemp)"
( python3 - >"$TEMP_RAW" 2>/dev/null <<'PY'
import ctypes, ctypes.util
iokit = ctypes.CDLL(ctypes.util.find_library("IOKit"))
cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
vp = ctypes.c_void_p
UTF8 = 0x08000100
TEMPERATURE_EVENT = 15

def bind(lib, name, restype, argtypes):
    function = getattr(lib, name)
    function.restype = restype
    function.argtypes = argtypes
    return function

client_create = bind(iokit, "IOHIDEventSystemClientCreate", vp, [vp])
client_set_matching = bind(iokit, "IOHIDEventSystemClientSetMatching", ctypes.c_int, [vp, vp])
client_copy_services = bind(iokit, "IOHIDEventSystemClientCopyServices", vp, [vp])
service_copy_property = bind(iokit, "IOHIDServiceClientCopyProperty", vp, [vp, vp])
service_copy_event = bind(iokit, "IOHIDServiceClientCopyEvent", vp, [vp, ctypes.c_int64, ctypes.c_int32, ctypes.c_int64])
event_get_float = bind(iokit, "IOHIDEventGetFloatValue", ctypes.c_double, [vp, ctypes.c_int32])
string_create = bind(cf, "CFStringCreateWithCString", vp, [vp, ctypes.c_char_p, ctypes.c_uint32])
string_get = bind(cf, "CFStringGetCString", ctypes.c_bool, [vp, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32])
number_create = bind(cf, "CFNumberCreate", vp, [vp, ctypes.c_int, vp])
dictionary_create = bind(cf, "CFDictionaryCreate", vp, [vp, vp, vp, ctypes.c_long, vp, vp])
array_count = bind(cf, "CFArrayGetCount", ctypes.c_long, [vp])
array_get = bind(cf, "CFArrayGetValueAtIndex", vp, [vp, ctypes.c_long])

def cf_string(text):
    return string_create(None, text.encode(), UTF8)

def cf_int(value):
    boxed = ctypes.c_int32(value)
    return number_create(None, 3, ctypes.byref(boxed))

keys = (vp * 2)(cf_string("PrimaryUsagePage"), cf_string("PrimaryUsage"))
values = (vp * 2)(cf_int(0xff00), cf_int(5))
key_callbacks = vp.in_dll(cf, "kCFTypeDictionaryKeyCallBacks")
value_callbacks = vp.in_dll(cf, "kCFTypeDictionaryValueCallBacks")
matching = dictionary_create(None, keys, values, 2, ctypes.addressof(key_callbacks), ctypes.addressof(value_callbacks))

client = client_create(None)
client_set_matching(client, matching)
services = client_copy_services(client)
product_key = cf_string("Product")

die_temps = []
for index in range(array_count(services) if services else 0):
    service = array_get(services, index)
    product = service_copy_property(service, product_key)
    name = ctypes.create_string_buffer(128)
    if not product or not string_get(product, name, 128, UTF8):
        continue
    if "tdie" not in name.value.decode():
        continue
    event = service_copy_event(service, TEMPERATURE_EVENT, 0, 0)
    if not event:
        continue
    celsius = event_get_float(event, TEMPERATURE_EVENT << 16)
    if 0 < celsius < 150:
        die_temps.append(celsius)

if die_temps:
    print(f"{sum(die_temps) / len(die_temps):.0f}\t{max(die_temps):.0f}")
PY
) &
TEMP_PID=$!

DISK_RAW="$(mktemp)"
(
  smart_status=""
  while IFS= read -r line; do
    case "$line" in
      *"SMART Status:"*)
        smart_status="${line#*SMART Status:}"
        smart_status="${smart_status#"${smart_status%%[![:space:]]*}"}"
        break ;;
    esac
  done < <(diskutil info disk0 2>/dev/null)
  disk_free="" disk_used_percent=""
  {
    read -r _
    read -r _ _ _ disk_free disk_used_percent _
  } < <(df -h /System/Volumes/Data 2>/dev/null)
  cycles=0 design=0 nominal=0 failure=0
  while IFS= read -r line; do
    case "$line" in
      *' "CycleCount" = '*) cycles="${line##*= }" ;;
      *' "DesignCapacity" = '*) design="${line##*= }" ;;
      *' "NominalChargeCapacity" = '*) nominal="${line##*= }" ;;
      *' "PermanentFailureStatus" = '*) failure="${line##*= }" ;;
    esac
  done < <(ioreg -rn AppleSmartBattery 2>/dev/null)
  battery_info=""
  if [ "$design" -gt 0 ] 2>/dev/null && [ "$nominal" -gt 0 ] 2>/dev/null; then
    battery_info="$(( nominal * 100 / design ))"$'\t'"$cycles"$'\t'"$failure"
  fi
  printf '%s\t%s\t%s\n%s\n' "$smart_status" "$disk_free" "${disk_used_percent%\%}" "$battery_info" >"$DISK_RAW"
) &
DISK_PID=$!

# --- Git: scan a base dir; one numstat pass per repo, count commits + sum lines.
# Populates globals: g_commits g_add g_del g_rows (safe if $1 doesn't exist —
# the unmatched glob fails the .git guard and the loop body is skipped).
scan_repos() {
  local base="$1" author="$2" d c a del
  g_commits=0; g_add=0; g_del=0; g_rows=""
  for d in "$base"/*/; do
    [ -d "$d/.git" ] || continue
    read -r c a del < <(git -C "$d" log --since="$SINCE" --author="$author" \
        --pretty=format:'C' --numstat 2>/dev/null \
        | awk '/^C/{c++} NF==3{a+=$1;del+=$2} END{print c+0, a+0, del+0}')
    [ "${c:-0}" -gt 0 ] || continue
    g_commits=$((g_commits + c)); g_add=$((g_add + a)); g_del=$((g_del + del))
    g_rows+="$(basename "$d")"$'\t'"$c"$'\t'"$a"$'\t'"$del"$'\n'
  done
}

scan_repos "$WORK" "$WORK_AUTHOR"
work_commits=$g_commits; work_add=$g_add; work_del=$g_del; work_rows=$g_rows
scan_repos "$PROJECTS" "$PROJ_AUTHOR"
proj_commits=$g_commits; proj_add=$g_add; proj_del=$g_del; proj_rows=$g_rows

total_commits=$((work_commits + proj_commits))

# --- Claude & Antigravity usage today: one jq call returns tab-delimited metrics ---
[ -n "$USAGE_PID" ] && wait "$USAGE_PID" 2>/dev/null
if [ -s "$USAGE_CACHE" ]; then
  IFS=$'\t' read -r tot_cost tot_htok c_cost c_htok c_models a_cost a_htok a_models < <(jq -r "$PARSE_USAGE_JQ" "$USAGE_CACHE" 2>/dev/null)
fi
tot_cost="${tot_cost:-0.00}"; tot_htok="${tot_htok:-0}"
c_cost="${c_cost:-0.00}"; c_htok="${c_htok:-0}"; c_models="${c_models:--}"
a_cost="${a_cost:-0.00}"; a_htok="${a_htok:-0}"; a_models="${a_models:--}"

# --- GitHub activity today ---
[ -n "$GH_PID" ] && wait "$GH_PID" 2>/dev/null
if [ -s "$GH_CACHE" ]; then
  IFS=$'\t' read -r gh_contributions gh_prs gh_opened gh_closed < <(jq -r --arg today "$TODAY_DASH" '
    .data
    | [([.viewer.contributionsCollection.contributionCalendar.weeks[].contributionDays[]
         | select(.date == $today) | .contributionCount] | add // 0),
       .prsOpened.issueCount,
       ([.authorOpened, .assigneeOpened] | map(.nodes[].url) | unique | length),
       ([.authorClosed, .assigneeClosed] | map(.nodes[].url) | unique | length)]
    | @tsv' "$GH_CACHE" 2>/dev/null)
fi
gh_opened="${gh_opened:-0}"; gh_closed="${gh_closed:-0}"
commit_title="${gh_contributions:-$total_commits}"
[ -n "$gh_prs" ] && commit_title+=" · PR ${gh_prs}"

wait "$TEMP_PID" 2>/dev/null
IFS=$'\t' read -r soc_avg soc_max < "$TEMP_RAW" 2>/dev/null

wait "$DISK_PID" 2>/dev/null
{
  IFS=$'\t' read -r smart_status disk_free disk_used_percent
  IFS=$'\t' read -r battery_health battery_cycles battery_failure
} < "$DISK_RAW" 2>/dev/null
rm -f "$TEMP_RAW" "$DISK_RAW"
disk_alert=""
case "$smart_status" in
  ""|Verified|"Not Supported") ;;
  *) disk_alert=1 ;;
esac
[ "${disk_used_percent:-0}" -gt 90 ] 2>/dev/null && disk_alert=1
battery_alert=""
if [ -n "$battery_health" ]; then
  [ "$battery_health" -lt 80 ] && battery_alert=1
  [ "${battery_failure:-0}" -ne 0 ] && battery_alert=1
fi
disk_free_percent=""
[[ "$disk_used_percent" =~ ^[0-9]+$ ]] && disk_free_percent=$((100 - disk_used_percent))
system_parts=()
[ -n "$soc_avg" ] && system_parts+=("${soc_avg}°C")
if [ -n "$disk_free_percent" ]; then
  system_parts+=("💾 ${disk_free_percent}% free")
elif [ -n "$disk_free" ]; then
  system_parts+=("💾 ${disk_free} free")
fi
[ -n "$disk_alert" ] && system_parts+=("⚠️ disk")
[ -n "$battery_alert" ] && system_parts+=("⚠️ battery")
system_title=""
for part in "${system_parts[@]}"; do
  system_title+="${system_title:+ · }${part}"
done

# --- Render a "base<TAB>commits<TAB>add<TAB>del" repo table under a heading ---
print_section() {
  local title="$1" base="$2" commits="$3" add="$4" del="$5" rows="$6"
  echo "${title} · ${commits} commits · +${add}/-${del} | font=Menlo"
  if [ -n "${rows//[$'\n\t']/}" ]; then
    printf '%s' "$rows" | while IFS=$'\t' read -r name c a d; do
      [ -n "$name" ] || continue
      printf '%s  %scmmt  +%s/-%s | font=Menlo size=12 href=file://%s/%s\n' "$name" "$c" "$a" "$d" "$base" "$name"
    done
  else
    echo "— no commits yet today | font=Menlo size=12 color=gray"
  fi
}

# ================= SwiftBar output =================
# Title lines before the first "---" cycle (rotate ~5s) in the menu bar —
# narrower than one long line, since the menu bar can't stack rows vertically.
echo "<> ${commit_title} | font=Menlo size=13"
echo "🐛 ↑${gh_opened}/↓${gh_closed} | font=Menlo size=13"
echo "\$${tot_cost} · ${tot_htok} | font=Menlo size=13"
[ -n "$system_title" ] && echo "${system_title} | font=Menlo size=13"
echo "---"
print_section "Work today" "$WORK" "$work_commits" "$work_add" "$work_del" "$work_rows"
echo "---"
print_section "Projects today" "$PROJECTS" "$proj_commits" "$proj_add" "$proj_del" "$proj_rows"
echo "---"
echo "Claude today · \$${c_cost} · ${c_htok} tok | font=Menlo"
[ "$c_models" != "-" ] && echo "models: ${c_models} | font=Menlo size=12 color=gray"
echo "Antigravity today · \$${a_cost} · ${a_htok} tok | font=Menlo"
[ "$a_models" != "-" ] && echo "models: ${a_models} | font=Menlo size=12 color=gray"
[ -n "$gh_contributions" ] && echo "GitHub today · ${gh_contributions} contributions · ${gh_prs} PRs | font=Menlo"
echo "Issues today · ↑${gh_opened} opened · ↓${gh_closed} closed | font=Menlo"
echo "author or assignee · github.com/$GITHUB_USER | font=Menlo size=12 color=gray href=https://github.com/$GITHUB_USER"
[ -n "$soc_avg" ] && echo "SoC temp · avg ${soc_avg}°C · max ${soc_max}°C | font=Menlo"
if [ -n "$smart_status" ] || [ -n "$disk_free" ]; then
  disk_line="Disk · SMART ${smart_status:-unknown}"
  [ -n "$disk_free" ] && disk_line+=" · ${disk_free} free${disk_free_percent:+ (${disk_free_percent}%)}"
  disk_style="font=Menlo"
  [ -n "$disk_alert" ] && disk_style+=" color=red"
  echo "${disk_line} | ${disk_style}"
fi
if [ -n "$battery_health" ]; then
  battery_style="font=Menlo"
  [ -n "$battery_alert" ] && battery_style+=" color=red"
  echo "Battery · ${battery_health}% health · ${battery_cycles} cycles | ${battery_style}"
fi
echo "---"
echo "Updated ${NOW_HM} | size=11 color=gray"
echo "Refresh | refresh=true"
