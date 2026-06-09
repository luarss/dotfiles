#!/usr/bin/env bash
# Remote Command Guard — PreToolUse hook (matcher: Bash)
# Blocks dangerous Bash commands in REMOTE / orchestrated Claude Code sessions.
#
# Wired in settings.base.json (all profiles). Exit codes: 0 = allow, 2 = block.
#
# Gating: this guard only runs when an orchestrator session var is set
# (OPENCLAW_SESSION_ID or HERMES_SESSION_ID). In normal interactive local
# sessions neither is set, so the guard no-ops and never gets in your way —
# day-to-day curl/ssh/sudo/kill stay allowed. The moment work is driven by
# openclaw or the hermes-agent, the full block list below kicks in.
#
# Blocked categories:
#   1. Destructive deletion (rm -rf /, rm -rf ~, rm -rf *, mkfs, dd of=/dev/…)
#   2. Env/secret leakage (env, printenv, echo $SECRET, cat .env / credentials)
#   3. Path traversal (/etc/passwd, /etc/shadow, /proc/<pid>, ../etc …)
#   4. External communication (curl, wget, nc, ssh, scp, rsync host:, …)
#   5. Permission changes (chmod 777/666, chown, mount, sudo, su, dscl)
#   6. Process termination (kill -9, pkill, killall, shutdown, reboot)
#   7. Command injection (eval, exec, pipe-to-shell, base64 -d | sh)
#
# Adapted from sangrokjung/claude-forge hooks/remote-command-guard.sh:
#   https://github.com/sangrokjung/claude-forge/blob/main/hooks/remote-command-guard.sh
# Comments translated to English and the gate widened to cover hermes-agent;
# command extraction switched to jq to match this repo's convention.

# Skip unless this is an orchestrated/remote session.
if [[ -z "${OPENCLAW_SESSION_ID:-}" && -z "${HERMES_SESSION_ID:-}" ]]; then
    exit 0
fi

INPUT=$(cat)

COMMAND=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Pass the command via env var (avoids shell re-expansion), then run the
# pattern checks in Python where the regexes are easiest to read.
export _GUARD_CMD="$COMMAND"
python3 << 'GUARD_SCRIPT'
import os
import sys
import re

command = os.environ.get("_GUARD_CMD", "")
if not command:
    sys.exit(0)

# Normalize whitespace (collapse runs of spaces into one).
cmd = re.sub(r'\s+', ' ', command.strip())
cmd_lower = cmd.lower()

blocked_reason = None

# === 1. Destructive deletion ===
# Only block broad/recursive wipes; deleting a specific file is allowed.
destructive_patterns = [
    r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\s',  # rm -rf, rm -rfi, …
    r'\brm\s+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*\s',  # rm -fr, rm -fri, …
    r'\brm\b.*\s+/$',                              # rm / (root)
    r'\brm\b.*\s+/\s',                             # rm / something
    r'\brm\b.*\s+~/?(\s|$)',                       # rm ~ or rm ~/
    r'\brm\b.*\s+\*(\s|$)',                        # rm * (whole cwd)
    r'\bmkfs\b',
    r'\bdd\s+.*of=/dev/',
    r'\b:\s*\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;',  # fork bomb
]
for pat in destructive_patterns:
    if re.search(pat, cmd_lower):
        blocked_reason = "destructive deletion command detected"
        break

# === 2. Env/secret leakage ===
# Match against original cmd with IGNORECASE to preserve env-var name casing.
if not blocked_reason:
    secret_patterns = [
        r'\b(env|printenv|set)\s*$',
        r'\b(env|printenv|set)\s*\|',
        r'\becho\s+.*\$[A-Z_]*KEY\b',
        r'\becho\s+.*\$[A-Z_]*SECRET\b',
        r'\becho\s+.*\$[A-Z_]*TOKEN\b',
        r'\becho\s+.*\$[A-Z_]*PASSWORD\b',
        r'\becho\s+.*\$[A-Z_]*PASSWD\b',
        r'\becho\s+.*\$[A-Z_]*API\b',
        r'\becho\s+.*\$[A-Z_]*CREDENTIAL\b',
        r'\becho\s+.*\$(AWS_|OPENAI_|ANTHROPIC_|TELEGRAM_|GITHUB_|SUPABASE_)',
        r'\bcat\s+.*\.env\b',
        r'\bcat\s+.*\.netrc\b',
        r'\bcat\s+.*credentials\b',
        r'\bcat\s+.*/\.ssh/',
        r'\bexport\s+-p\s*$',
        r'\bexport\s+-p\s*\|',
    ]
    for pat in secret_patterns:
        if re.search(pat, cmd, re.IGNORECASE):
            blocked_reason = "secret/env-var leakage attempt detected"
            break

# === 3. Path traversal ===
if not blocked_reason:
    path_traversal_patterns = [
        r'/etc/passwd',
        r'/etc/shadow',
        r'/etc/sudoers',
        r'/etc/master\.passwd',
        r'\.\./(\.\./)*(etc|proc|sys|dev)/',
        r'/proc/self/',
        r'/proc/\d+/',
        r'/sys/class/',
    ]
    for pat in path_traversal_patterns:
        if re.search(pat, cmd_lower):
            blocked_reason = "sensitive system path access detected"
            break

# === 4. External communication ===
if not blocked_reason:
    network_patterns = [
        r'\bcurl\s',
        r'\bwget\s',
        r'\bnc\s',
        r'\bncat\s',
        r'\bnetcat\s',
        r'\btelnet\s',
        r'\bssh\s',
        r'\bscp\s',
        r'\brsync\s.*:',
        r'\bftp\s',
        r'\bsftp\s',
        r'\bsocat\s',
        r'\bpython3?\s+-m\s+http\.server',
        r'\bphp\s+-S\s',
        r'\bnpm\s+publish\b',
        r'\bnpx\s.*ngrok',
    ]
    # Allow curl/wget to localhost (dev use).
    is_local = bool(re.search(
        r'\bcurl\s+.*\b(localhost|127\.0\.0\.1|0\.0\.0\.0)\b', cmd_lower
    ))
    if not is_local:
        for pat in network_patterns:
            if re.search(pat, cmd_lower):
                blocked_reason = "external network communication attempt detected"
                break

# === 5. Permission changes ===
if not blocked_reason:
    permission_patterns = [
        r'\bchmod\s+777\b',
        r'\bchmod\s+666\b',
        r'\bchmod\s+[0-7]*[67][0-7]{2}\b.*/(etc|usr|var|sys)',
        r'\bchown\s',
        r'\bmount\s',
        r'\bumount\s',
        r'\bsudo\s',
        r'\bsu\s+-?\s',
        r'\bdscl\s',
    ]
    for pat in permission_patterns:
        if re.search(pat, cmd_lower):
            blocked_reason = "permission change command detected"
            break

# === 6. Process termination ===
if not blocked_reason:
    process_patterns = [
        r'\bkill\s+-9\b',
        r'\bkill\s+-KILL\b',
        r'\bkill\s+-SIGKILL\b',
        r'\bkillall\s',
        r'\bpkill\s',
        r'\bxkill\b',
        r'\bshutdown\b',
        r'\breboot\b',
        r'\bhalt\b',
        r'\binit\s+[06]\b',
    ]
    for pat in process_patterns:
        if re.search(pat, cmd_lower):
            blocked_reason = "process termination / system control command detected"
            break

# === 7. Command injection ===
if not blocked_reason:
    injection_patterns = [
        r'\beval\s',
        r'\bexec\s',
        r'\bsource\s+/dev/',
        r'\bbash\s+-c\s.*\$\(',
        r'\bsh\s+-c\s.*\$\(',
        r'`[^`]*\$\([^)]+\)[^`]*`',
        r'\|\s*sh\b',
        r'\|\s*bash\b',
        r'\|\s*zsh\b',
        r'>\s*/dev/sd[a-z]',
        r'>\s*/dev/nvme',
        r'\bbase64\s+-d\s*\|\s*(sh|bash|zsh)',
    ]
    for pat in injection_patterns:
        if re.search(pat, cmd_lower):
            blocked_reason = "command injection pattern detected"
            break

if blocked_reason:
    safe_cmd = cmd[:200]
    print(f"BLOCKED: {blocked_reason}", file=sys.stderr)
    print(f"Command: {safe_cmd}", file=sys.stderr)
    sys.exit(2)

sys.exit(0)
GUARD_SCRIPT
