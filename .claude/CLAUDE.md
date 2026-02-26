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
