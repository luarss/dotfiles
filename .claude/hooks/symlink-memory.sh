#!/usr/bin/env bash
# PostToolUse hook (Write|Edit) — for any memory file saved under
# ~/.claude*/projects/<encoded>/memory/, mirror it into the Obsidian vault and
# append an entry to the vault's Index.md (if it exists).
#
# Mirrors via file copy (not symlink) so the notes repo renders on GitHub.
# The mirror is one-way: edits in the Obsidian copy do NOT propagate back to
# the ~/.claude memory source.
#
# Idempotent: skips if the memory file is already referenced in Index.md, so
# manual edits to existing entries are preserved.
#
# Wired globally in ~/.claude/settings.json.
set -e

PAYLOAD=$(cat)
FILE_PATH=$(jq -r '.tool_input.file_path // empty' <<<"$PAYLOAD")
CWD=$(jq -r '.cwd // empty' <<<"$PAYLOAD")

[[ -z "$FILE_PATH" || -z "$CWD" ]] && exit 0
[[ "$FILE_PATH" =~ /\.claude[^/]*/projects/-[^/]+/memory/[^/]+\.md$ ]] || exit 0
[[ "$(basename "$FILE_PATH")" == "MEMORY.md" ]] && exit 0
[[ -f "$FILE_PATH" ]] || exit 0

# Skip cross-project edits: only mirror when the session's cwd is the project
# the memory belongs to. Compare the encoded form of CWD against the project
# segment of FILE_PATH. The encoding is lossy (slashes and dashes collide),
# so deriving FRIENDLY from FILE_PATH alone isn't reliable — CWD is the
# unambiguous source of the project's basename.
ENCODED_PROJECT=$(basename "$(dirname "$(dirname "$FILE_PATH")")")
ENCODED_CWD="${CWD//\//-}"
[[ "$ENCODED_PROJECT" == "$ENCODED_CWD" ]] || exit 0

FRIENDLY=$(basename "$CWD")
FRIENDLY="${FRIENDLY//-/_}"
LEARNING_DIR="$HOME/work/notes/NUS-Enterprise/Reflections/Learning"
TARGET="$LEARNING_DIR/memory_$FRIENDLY"

# 1) Mirror as a file copy (not symlink) so GitHub can render it
mkdir -p "$TARGET"
DEST="$TARGET/$(basename "$FILE_PATH")"
[[ -L "$DEST" || -e "$DEST" ]] && rm -f "$DEST"
cp "$FILE_PATH" "$DEST"

# 2) Update Index.md (no-op if missing)
INDEX="$LEARNING_DIR/Index.md"
[[ -f "$INDEX" ]] || exit 0

BASENAME_NOEXT="$(basename "$FILE_PATH" .md)"
LINK_FRAG="[[memory_${FRIENDLY}/${BASENAME_NOEXT}"

# Skip if this memory is already referenced anywhere in the index
grep -qF "$LINK_FRAG" "$INDEX" && exit 0

# Pull title + blurb from YAML frontmatter (best-effort; falls back to filename)
NAME=$(awk '
  /^---$/ { c++; if (c == 2) exit; next }
  c == 1 && /^name:/ {
    sub(/^name:[[:space:]]*/, "")
    sub(/^"/, ""); sub(/"$/, "")
    sub(/^'\''/, ""); sub(/'\''$/, "")
    print; exit
  }
' "$FILE_PATH")

DESC=$(awk '
  /^---$/ { c++; if (c == 2) exit; next }
  c == 1 && /^description:/ {
    sub(/^description:[[:space:]]*/, "")
    sub(/^"/, ""); sub(/"$/, "")
    sub(/^'\''/, ""); sub(/'\''$/, "")
    print; exit
  }
' "$FILE_PATH")

TITLE="${NAME:-$BASENAME_NOEXT}"
if [[ -n "$DESC" ]]; then
  BULLET="- ${LINK_FRAG}|${TITLE}]] — ${DESC}"
else
  BULLET="- ${LINK_FRAG}|${TITLE}]]"
fi

SECTION_HEADER="## Claude Code memory (${FRIENDLY})"
ENCODED_NAME="$(basename "$(dirname "$(dirname "$FILE_PATH")")")"

if grep -qF "$SECTION_HEADER" "$INDEX"; then
  # Insert bullet right after the section's last bullet (or after its header
  # if the section has none yet).
  TMP=$(mktemp)
  HDR="$SECTION_HEADER" BULLET_LINE="$BULLET" awk '
    BEGIN {
      hdr = ENVIRON["HDR"]
      bullet = ENVIRON["BULLET_LINE"]
      in_sec = 0; idx = 0; insert_after = -1
    }
    {
      lines[++idx] = $0
      if (in_sec && /^## /) in_sec = 0
      if ($0 == hdr) { in_sec = 1; insert_after = idx }
      else if (in_sec && /^- \[\[memory_/) insert_after = idx
    }
    END {
      for (i = 1; i <= idx; i++) {
        print lines[i]
        if (i == insert_after) print bullet
      }
    }
  ' "$INDEX" > "$TMP"
  mv "$TMP" "$INDEX"
else
  # No section yet — append one at EOF
  {
    printf '\n%s\n\n' "$SECTION_HEADER"
    printf 'Copies into `memory_%s/` — one-way mirror of `~/.claude/projects/%s/memory/`. Edits here are NOT propagated back to the source.\n\n' \
      "$FRIENDLY" "$ENCODED_NAME"
    printf '%s\n' "$BULLET"
  } >> "$INDEX"
fi
