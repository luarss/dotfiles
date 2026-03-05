# Global Claude Instructions

## My Preferences

### Code Style
- Prefer **clear, readable** code over clever one-liners
- Add comments for non-obvious logic, skip for self-documenting code
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
Prefer LSP over Grep/Glob/Read for code navigation:
- `goToDefinition` / `goToImplementation` to jump to source
- `findReferences` to see all usages across the codebase
- `workspaceSymbol` to find where something is defined
- `documentSymbol` to list all symbols in a file
- `hover` for type info without reading the file
- `incomingCalls` / `outgoingCalls` for call hierarchy

Before renaming or changing a function signature, use
`findReferences` to find all call sites first.

Use Grep/Glob only for text/pattern searches (comments,
strings, config values) where LSP doesn't help.

After writing or editing code, check LSP diagnostics before
moving on. Fix any type errors or missing imports immediately.

## Project Patterns

### Monorepos
- Check for `turbo.json`, `pnpm-workspace.yaml`, or `nx.json` at root
- Run tasks through the workspace tool, not directly

### Python Projects
- Check for `pyproject.toml` or `setup.py` first
- Prefer `uv` for package management if available, otherwise `pip`
- Always activate virtualenv before running Python commands

### Node Projects
- Check `package.json` for scripts before running commands manually
- Prefer `pnpm` > `yarn` > `npm`

## Things to Avoid
- Don't over-explain unless I ask for it
