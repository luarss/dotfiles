#!/usr/bin/env bats

setup() {
  local base; base="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$base/scripts/archive-notes.sh"

  ROOT="$(mktemp -d)"
  export HOME="$ROOT/home"
  mkdir -p "$HOME/.claude"

  export NOTES_ARCHIVE_SOURCE_DIR="$ROOT/notes"
  export NOTES_ARCHIVE_DIR="$ROOT/archive"
  mkdir -p "$NOTES_ARCHIVE_SOURCE_DIR/NUS-Enterprise" "$NOTES_ARCHIVE_DIR"
  echo "deck" > "$NOTES_ARCHIVE_SOURCE_DIR/NUS-Enterprise/deck.pptx"
  echo "note" > "$NOTES_ARCHIVE_SOURCE_DIR/NUS-Enterprise/note.md"

  TODAY="$(date +%Y-%m-%d)"
}

teardown() { rm -rf "$ROOT"; }

@test "mirrors files, including git-ignored binaries, into current/" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$NOTES_ARCHIVE_DIR/current/NUS-Enterprise/deck.pptx" ]
  [ -f "$NOTES_ARCHIVE_DIR/current/NUS-Enterprise/note.md" ]
}

@test "excludes .git, .venv-pptx, .scratch and the .claude symlink" {
  mkdir -p "$NOTES_ARCHIVE_SOURCE_DIR/.git" "$NOTES_ARCHIVE_SOURCE_DIR/.venv-pptx" "$NOTES_ARCHIVE_SOURCE_DIR/.scratch" "$NOTES_ARCHIVE_SOURCE_DIR/.agents"
  echo x > "$NOTES_ARCHIVE_SOURCE_DIR/.git/HEAD"
  echo x > "$NOTES_ARCHIVE_SOURCE_DIR/.venv-pptx/lib"
  echo x > "$NOTES_ARCHIVE_SOURCE_DIR/.scratch/tmp"
  ln -s .agents "$NOTES_ARCHIVE_SOURCE_DIR/.claude"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$NOTES_ARCHIVE_DIR/current/.git" ]
  [ ! -e "$NOTES_ARCHIVE_DIR/current/.venv-pptx" ]
  [ ! -e "$NOTES_ARCHIVE_DIR/current/.scratch" ]
  [ ! -e "$NOTES_ARCHIVE_DIR/current/.claude" ]
  [ -d "$NOTES_ARCHIVE_DIR/current/.agents" ]
}

@test "a deleted source file is preserved under versions/<date>/" {
  bash "$SCRIPT"
  rm "$NOTES_ARCHIVE_SOURCE_DIR/NUS-Enterprise/deck.pptx"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$NOTES_ARCHIVE_DIR/current/NUS-Enterprise/deck.pptx" ]
  [ -f "$NOTES_ARCHIVE_DIR/versions/$TODAY/NUS-Enterprise/deck.pptx" ]
}

@test "an overwritten source file keeps its previous content under versions/<date>/" {
  bash "$SCRIPT"
  echo "revised" > "$NOTES_ARCHIVE_SOURCE_DIR/NUS-Enterprise/note.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$NOTES_ARCHIVE_DIR/current/NUS-Enterprise/note.md")" = "revised" ]
  [ "$(cat "$NOTES_ARCHIVE_DIR/versions/$TODAY/NUS-Enterprise/note.md")" = "note" ]
}

@test "dry run writes nothing" {
  run env NOTES_ARCHIVE_DRY_RUN=1 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [ ! -e "$NOTES_ARCHIVE_DIR/current/NUS-Enterprise/note.md" ]
}

@test "no-op when the archive dir is absent" {
  export NOTES_ARCHIVE_DIR="$ROOT/missing"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [ ! -e "$ROOT/missing" ]
}

@test "exits quietly when another run holds the lock" {
  mkdir "$HOME/.claude/.archive-notes.lock"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"holds the lock"* ]]
  [ ! -e "$NOTES_ARCHIVE_DIR/current/NUS-Enterprise/note.md" ]
}
