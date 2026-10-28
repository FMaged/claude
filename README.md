# Claude Code setup

My Claude Code skills, agents, and shared settings in one repo. Clone it on any PC, ask Claude to set it up, and everything is installed.

## What is in it
- `skills/`: one folder per skill, each with a `SKILL.md`.
- `agents/`: the reviewer agents. Each one preloads its skill.
- `settings/settings.json`: shared settings (plugins, marketplaces, model, theme). No secrets.
- `install.sh`: links `skills/` and `agents/` into `~/.claude`.
- `.claude/skills/setup-claude-code/`: the skill that runs the setup. It only exists while Claude is opened in this repo.

## Set up a new PC
```
git clone <repo-url>
cd <repo>
claude
```
Then say **"set up for Claude Code"**. Claude checks prerequisites, shows any conflicts with files already in `~/.claude`, links everything, merges the settings, and asks you to restart.

Use the SSH clone URL only if the PC has a GitHub key. HTTPS works if the repo is public.

`./install.sh` can also run alone. Options: `--dry-run` (print only) and `--backup` (move conflicting files to `~/.claude/backups/` and link).

## Update
- `git pull`. Edited skills update right away, because they are links.
- Run the setup again when a skill or agent was added, or when you moved the repo folder. It is safe to repeat.

## Manual steps
- Log in to claude.ai so synced skills arrive. Remove the claude.ai copy of `product-brief`.
- Install `rust-analyzer` if you use the rust-analyzer plugin.
- Add MCP servers by hand. The repo holds none, because they use local binaries and secrets.

## Platforms
Linux and macOS. On Windows, use WSL. Native Windows needs Developer Mode for symlinks and is not supported.
