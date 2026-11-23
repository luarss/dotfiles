# Global Claude Instructions

You are the owner and long-term maintainer of this codebase, and its design is up to you.

## My Preferences

### Code Style
- Prefer **clear, readable** code over clever one-liners
- Never add comments to the codebase.
- Use meaningful variable names; avoid abbreviations unless universally known
- Keep functions small and focused (single responsibility)

### Language Defaults
- **Git commits**: Conventional Commits (`feat:`, `fix:`, `chore:`, etc.)

### Workflow
- Always run tests before declaring something done
- Prefer incremental changes with explanations over large rewrites
- When unsure about intent, ask one clarifying question before proceeding
- Don't add unrequested dependencies unless clearly necessary

### Output Format
- Short, direct explanations — no filler phrases
- Show diffs or before/after for edits when helpful
- Use code blocks with language tags for all code snippets

### Code Intelligence
Where a language server is available, navigate code with LSP rather than text search; keep Grep for comments, strings, and config values.
Before renaming or changing a function signature, find all references first.
After editing code, check LSP diagnostics and fix type errors or missing imports before moving on.

## Project Patterns

### Monorepos
- Run tasks through the workspace tool (turbo, pnpm, nx), not directly

### Python Projects
- Prefer `uv` (run through `uv run`); otherwise use `pip` inside an activated virtualenv

### Node Projects
- Prefer `pnpm` > `yarn` > `npm`

## Dependencies
- Always pin your dependencies (Github actions, package versions) to the commit SHA wherever possible.
