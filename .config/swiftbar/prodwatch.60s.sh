#!/bin/bash
# SwiftBar productivity widget: today's git activity + Claude usage.
# Refreshes every 60s (filename ".60s."). Deliberately lightweight: one git
# pass per repo, one node call, active repos only.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"

WORK="$HOME/work"
SINCE="$(date +%Y-%m-%dT00:00:00)"
AUTHOR="song.luar@a5x.ai"

# Kick off ccusage (the slow half) in the background so it overlaps the git scan.
USAGE_RAW="$(mktemp)"
( ccusage daily --json --since "$(date +%Y%m%d)" >"$USAGE_RAW" 2>/dev/null ) &
USAGE_PID=$!

# --- Git: single numstat pass per repo; count commits + sum lines in one awk ---
total_commits=0; total_add=0; total_del=0; rows=""
for d in "$WORK"/*/; do
  [ -d "$d/.git" ] || continue
  read -r c a del < <(git -C "$d" log --since="$SINCE" --author="$AUTHOR" \
      --pretty=format:'C' --numstat 2>/dev/null \
      | awk '/^C/{c++} NF==3{a+=$1;del+=$2} END{print c+0, a+0, del+0}')
  [ "${c:-0}" -gt 0 ] || continue
  total_commits=$((total_commits + c)); total_add=$((total_add + a)); total_del=$((total_del + del))
  rows+="$(basename "$d")"$'\t'"$c"$'\t'"$a"$'\t'"$del"$'\n'
done

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

# ================= SwiftBar output =================
echo "⚡ ${total_commits}cmmt · \$${cost} · ${htok} | font=Menlo size=13"
echo "---"
echo "Git today · ${total_commits} commits · +${total_add}/-${total_del} | font=Menlo"
if [ -n "${rows//[$'\n\t']/}" ]; then
  printf '%s' "$rows" | while IFS=$'\t' read -r name c a del; do
    [ -n "$name" ] || continue
    printf '%s  %scmmt  +%s/-%s | font=Menlo size=12 href=file://%s/%s\n' "$name" "$c" "$a" "$del" "$WORK" "$name"
  done
else
  echo "— no commits yet today | font=Menlo size=12 color=gray"
fi
echo "---"
echo "Claude today · \$${cost} · ${htok} tok | font=Menlo"
[ "$models" != "-" ] && echo "models: ${models} | font=Menlo size=12 color=gray"
echo "---"
echo "Updated $(date +%H:%M) | size=11 color=gray"
echo "Refresh | refresh=true"
