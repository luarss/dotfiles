#!/bin/bash
# SwiftBar productivity widget: today's git activity + Claude usage.
# Refreshes every 60s (filename ".60s."). Deliberately lightweight: one git
# pass per repo, one node call, active repos only.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"

WORK="$HOME/work"
PROJECTS="$HOME/projects"
SINCE="$(date +%Y-%m-%dT00:00:00)"
# --author is a regex; \| alternation lets one scan match several identities.
WORK_AUTHOR="song.luar@a5x.ai"
# ~/projects repos commit under the personal GitHub noreply identity too.
PROJ_AUTHOR="song.luar@a5x.ai\|luarss@users.noreply.github.com"

# Kick off ccusage (the slow half) in the background so it overlaps the git scan.
USAGE_RAW="$(mktemp)"
( ccusage daily --json --since "$(date +%Y%m%d)" >"$USAGE_RAW" 2>/dev/null ) &
USAGE_PID=$!

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

# --- Claude usage today: one node call returns "cost<TAB>htok<TAB>models" ---
wait "$USAGE_PID" 2>/dev/null
read -r cost htok models < <(node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const t=JSON.parse(s).daily?.slice(-1)[0];
    if(!t){console.log("0\t0\t-");return;}
    const n=t.totalTokens||0;
    const h=n>=1e6?(n/1e6).toFixed(1)+"M":n>=1e3?(n/1e3).toFixed(0)+"k":""+n;
    const m=(t.modelsUsed||[]).map(x=>x.replace(/claude-|-\d.*$/g,"")).join(",")||"-";
    console.log(t.totalCost.toFixed(2)+"\t"+h+"\t"+m);
  }catch(e){console.log("0\t0\t-");}
});' 2>/dev/null < "$USAGE_RAW")
rm -f "$USAGE_RAW"
cost="${cost:-0}"; htok="${htok:-0}"

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
echo "⚡ ${total_commits}cmmt · \$${cost} · ${htok} | font=Menlo size=13"
echo "---"
print_section "Work today" "$WORK" "$work_commits" "$work_add" "$work_del" "$work_rows"
echo "---"
print_section "Projects today" "$PROJECTS" "$proj_commits" "$proj_add" "$proj_del" "$proj_rows"
echo "---"
echo "Claude today · \$${cost} · ${htok} tok | font=Menlo"
[ "$models" != "-" ] && echo "models: ${models} | font=Menlo size=12 color=gray"
echo "github.com/luarss | font=Menlo size=12 href=https://github.com/luarss"
echo "---"
echo "Updated $(date +%H:%M) | size=11 color=gray"
echo "Refresh | refresh=true"
