#!/bin/bash
# SwiftBar productivity widget: today's git activity + Claude/Antigravity usage.
# Refreshes every 60s (filename ".60s."). Deliberately lightweight: one git
# pass per repo, one node call, active repos only.
export PATH="$PATH:/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin"

WORK="$HOME/work"
PROJECTS="$HOME/projects"
SINCE="$(date +%Y-%m-%dT00:00:00)"
# --author is a regex; \| alternation lets one scan match several identities.
WORK_AUTHOR="song.luar@a5x.ai"
# ~/projects repos commit under the personal GitHub noreply identity too.
PROJ_AUTHOR="song.luar@a5x.ai\|luarss@users.noreply.github.com"

# Kick off ccusage (the slow half) in the background so it overlaps the git scan.
USAGE_RAW="$(mktemp)"
( ccusage daily --json --by-agent --since "$(date +%Y%m%d)" >"$USAGE_RAW" 2>/dev/null ) &
USAGE_PID=$!

# Kick off GitHub issue counts (network-bound) in the background too. Counts
# distinct issues opened/closed today where I'm the author OR assignee — four
# search-API calls (30/min budget), deduped by repo#number so an issue that is
# both authored and assigned isn't double-counted. Writes "opened<TAB>closed".
GH_RAW="$(mktemp)"
(
  if command -v gh >/dev/null 2>&1; then
    gh_today="$(date +%Y-%m-%d)"
    issue_keys() {
      gh search issues "$@" --limit 100 --json number,repository \
        -q '.[] | "\(.repository.nameWithOwner)#\(.number)"' 2>/dev/null
    }
    opened=$( { issue_keys --author=@me --created=">=$gh_today"
               issue_keys --assignee=@me --created=">=$gh_today"; } | sort -u | grep -c . )
    closed=$( { issue_keys --author=@me --closed=">=$gh_today"
               issue_keys --assignee=@me --closed=">=$gh_today"; } | sort -u | grep -c . )
    printf '%s\t%s\n' "${opened:-0}" "${closed:-0}" >"$GH_RAW"
  fi
) &
GH_PID=$!

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
  smart_status="$(diskutil info disk0 2>/dev/null | awk -F': *' '/SMART Status/{print $2; exit}')"
  read -r disk_free disk_used_percent < <(df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4, $5}')
  printf '%s\t%s\t%s\n' "$smart_status" "$disk_free" "${disk_used_percent%\%}" >"$DISK_RAW"
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

# --- Claude & Antigravity usage today: one node call returns tab-delimited metrics ---
wait "$USAGE_PID" 2>/dev/null
read -r tot_cost tot_htok c_cost c_htok c_models a_cost a_htok a_models < <(node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{
    const json=JSON.parse(s);
    const t=json.daily?.slice(-1)[0];
    if(!t){console.log("0.00\t0\t0.00\t0\t-\t0.00\t0\t-");return;}
    const fmtTok = n => {
      n = Number(n) || 0;
      return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? (n / 1e3).toFixed(0) + "k" : "" + n;
    };
    const cleanModels = list => {
      const cleaned = (list || [])
        .map(x => x.replace(/^(claude|gemini)-/, "").replace(/-\d{8}$/, ""))
        .filter(Boolean);
      return [...new Set(cleaned)].join(",") || "-";
    };

    const agents = Array.isArray(t.agents) ? t.agents : [];
    let c = agents.find(x => x.agent === "claude" || x.agent?.toLowerCase() === "claude");
    let a = agents.find(x => x.agent === "antigravity" || x.agent?.toLowerCase() === "antigravity");

    if (!c && !a && t.metadata?.agents) {
      if (t.metadata.agents.includes("claude") && !t.metadata.agents.includes("antigravity")) c = t;
      else if (t.metadata.agents.includes("antigravity") && !t.metadata.agents.includes("claude")) a = t;
    }

    const cCost = Number(c?.totalCost || 0).toFixed(2);
    const cTok = fmtTok(c?.totalTokens);
    const cModels = cleanModels(c?.modelsUsed);

    const aCost = Number(a?.totalCost || 0).toFixed(2);
    const aTok = fmtTok(a?.totalTokens);
    const aModels = cleanModels(a?.modelsUsed);

    const totCost = Number(t.totalCost || 0).toFixed(2);
    const totTok = fmtTok(t.totalTokens);

    console.log([totCost, totTok, cCost, cTok, cModels, aCost, aTok, aModels].join("\t"));
  }catch(e){console.log("0.00\t0\t0.00\t0\t-\t0.00\t0\t-");}
});' 2>/dev/null < "$USAGE_RAW")
rm -f "$USAGE_RAW"
tot_cost="${tot_cost:-0.00}"; tot_htok="${tot_htok:-0}"
c_cost="${c_cost:-0.00}"; c_htok="${c_htok:-0}"; c_models="${c_models:--}"
a_cost="${a_cost:-0.00}"; a_htok="${a_htok:-0}"; a_models="${a_models:--}"

# --- GitHub issues today ---
wait "$GH_PID" 2>/dev/null
IFS=$'\t' read -r gh_opened gh_closed < "$GH_RAW" 2>/dev/null
rm -f "$GH_RAW"
gh_opened="${gh_opened:-0}"; gh_closed="${gh_closed:-0}"

wait "$TEMP_PID" 2>/dev/null
IFS=$'\t' read -r soc_avg soc_max < "$TEMP_RAW" 2>/dev/null
rm -f "$TEMP_RAW"

wait "$DISK_PID" 2>/dev/null
IFS=$'\t' read -r smart_status disk_free disk_used_percent < "$DISK_RAW" 2>/dev/null
rm -f "$DISK_RAW"
disk_alert=""
case "$smart_status" in
  ""|Verified|"Not Supported") ;;
  *) disk_alert=1 ;;
esac
[ "${disk_used_percent:-0}" -gt 90 ] 2>/dev/null && disk_alert=1
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
echo "<> ${total_commits} · 🐛 ↑${gh_opened}/↓${gh_closed} | font=Menlo size=13"
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
echo "Issues today · ↑${gh_opened} opened · ↓${gh_closed} closed | font=Menlo"
echo "author or assignee · github.com/luarss | font=Menlo size=12 color=gray href=https://github.com/luarss"
[ -n "$soc_avg" ] && echo "SoC temp · avg ${soc_avg}°C · max ${soc_max}°C | font=Menlo"
if [ -n "$smart_status" ] || [ -n "$disk_free" ]; then
  disk_line="Disk · SMART ${smart_status:-unknown}"
  [ -n "$disk_free" ] && disk_line+=" · ${disk_free} free${disk_free_percent:+ (${disk_free_percent}%)}"
  disk_style="font=Menlo"
  [ -n "$disk_alert" ] && disk_style+=" color=red"
  echo "${disk_line} | ${disk_style}"
fi
echo "---"
echo "Updated $(date +%H:%M) | size=11 color=gray"
echo "Refresh | refresh=true"
