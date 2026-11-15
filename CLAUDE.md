# Claude Code and Codex setup

This repo holds shared Claude Code and Codex skills, plus Claude-specific agents and settings. The files here are the only source. Edit shared skills here, not through their installed links.

- "Set up for Claude Code" (or "set up this PC") means run the `setup-claude-code` skill.
- `skills/` is linked into `~/.claude/skills` and `~/.agents/skills` for Codex. `agents/` is linked only into `~/.claude/agents`.
- `./install.sh` installs for both clients by default; `--target claude` or `--target codex` selects one. Settings and instruction files are not installed by this script.
- A new skill goes in `skills/<name>/SKILL.md`. Then run `./install.sh` to link it.
- Commit with the `git-commit` skill.
- Never put secrets, credentials, or MCP server config in this repo.
