#!/usr/bin/env bash
# Replay `cd` commands from zsh history to seed zoxide's database.
#
# Walks history sequentially, tracking a virtual cwd so relative paths
# (cd ../foo) resolve correctly. Only directories that still exist get
# added. Use --dry-run to preview without touching the db.

set -eu

HIST_FILE="${HISTFILE:-$HOME/.zsh_history}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --hist-file=*) HIST_FILE="${arg#*=}" ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--dry-run] [--hist-file=PATH]

Replays cd commands from zsh history and seeds zoxide.
Default history file: \$HISTFILE or ~/.zsh_history
EOF
      exit 0
      ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -r "$HIST_FILE" ]; then
  echo "history file not readable: $HIST_FILE" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 0 ] && ! command -v zoxide >/dev/null 2>&1; then
  echo "zoxide not installed" >&2
  exit 1
fi

python3 - "$HIST_FILE" "$DRY_RUN" <<'PY'
import os, re, sys, subprocess
from collections import Counter

hist_path, dry_run = sys.argv[1], sys.argv[2] == "1"
home = os.path.expanduser("~")
cwd = home
prev = home

# zsh extended history: ": <ts>:<dur>;<cmd>" (cmd may contain ; etc)
entry_re = re.compile(r"^: \d+:\d+;(.*)$")
counts = Counter()

def resolve(target):
    """Resolve a cd target against the virtual cwd. Returns abs path or None."""
    global cwd, prev
    t = target.strip()
    if not t or t == "~":
        return home
    if t == "-":
        return prev
    if t.startswith("~/"):
        t = home + t[1:]
    if t.startswith("/"):
        return os.path.normpath(t)
    return os.path.normpath(os.path.join(cwd, t))

with open(hist_path, "rb") as f:
    raw = f.read().decode("utf-8", errors="replace")

# Join multi-line history entries (lines ending with backslash continue)
lines = []
buf = ""
for line in raw.splitlines():
    if buf:
        buf += "\n" + line
    else:
        buf = line
    if buf.endswith("\\"):
        buf = buf[:-1]
        continue
    lines.append(buf)
    buf = ""
if buf:
    lines.append(buf)

for line in lines:
    m = entry_re.match(line)
    cmd = m.group(1) if m else line
    cmd = cmd.strip()
    # Only handle the first command on the line (split on ; && ||)
    head = re.split(r"\s*(?:&&|\|\||;)\s*", cmd, maxsplit=1)[0].strip()
    if not head.startswith("cd"):
        continue
    rest = head[2:]
    if rest and not rest[0].isspace():
        continue  # e.g. "cdrom" — not a cd command
    arg = rest.strip()
    # Strip trailing comment
    arg = re.split(r"\s+#", arg, maxsplit=1)[0].strip()
    # Drop common flags like `cd -P`, `cd -L`
    while arg.startswith("-") and arg not in ("-",):
        parts = arg.split(None, 1)
        arg = parts[1] if len(parts) > 1 else ""
    # Unquote simple cases
    if len(arg) >= 2 and arg[0] == arg[-1] and arg[0] in ('"', "'"):
        arg = arg[1:-1]
    target = resolve(arg)
    if target is None:
        continue
    if os.path.isdir(target):
        counts[target] += 1
        prev, cwd = cwd, target
    # If the dir doesn't exist (anymore), don't update virtual cwd — the
    # real shell would have failed too, so subsequent relative cds in the
    # session resolved against the old cwd.

# Filter junk: keep only real directories under $HOME, exclude $HOME itself
# and noisy caches. zoxide is most useful for project/work dirs.
SKIP_PREFIXES = (
    os.path.join(home, "Library"),
    os.path.join(home, ".cache"),
    os.path.join(home, ".npm"),
    os.path.join(home, ".cargo"),
)

def keep(p):
    if p == home:
        return False
    if not (p + "/").startswith(home + "/"):
        return False
    for prefix in SKIP_PREFIXES:
        if (p + "/").startswith(prefix + "/"):
            return False
    return True

filtered = [(p, n) for p, n in counts.most_common() if keep(p)]
print(f"found {len(filtered)} unique directories from {sum(n for _, n in filtered)} cd events")

if dry_run:
    for p, n in filtered[:30]:
        print(f"  {n:4d}  {p}")
    if len(filtered) > 30:
        print(f"  ... and {len(filtered) - 30} more")
    sys.exit(0)

# Seed zoxide. `zoxide add` bumps the score by 1 per call, so call N times
# to reflect frequency. This preserves the relative ranking from history.
added = 0
for p, n in filtered:
    for _ in range(n):
        subprocess.run(["zoxide", "add", "--", p], check=True)
    added += 1

print(f"added {added} directories to zoxide")
PY
