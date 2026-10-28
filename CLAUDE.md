# Claude Code setup

This repo is my whole Claude Code setup: skills, agents, and shared settings. The files here are the only source. Nothing is edited in `~/.claude` directly.

- "Set up for Claude Code" (or "set up this PC") means run the `setup-claude-code` skill.
- `skills/` and `agents/` are linked into `~/.claude`, so editing them changes Claude on this PC right away.
- A new skill goes in `skills/<name>/SKILL.md`. Then run `./install.sh` to link it.
- Commit with the `git-commit` skill.
- Never put secrets, credentials, or MCP server config in this repo.
