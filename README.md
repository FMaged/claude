# Claude Code and Codex setup

Shared skills for Claude Code and Codex, plus Claude-specific agents and settings. Both clients use the same skill source files through symlinks.

## What is in it
- `skills/`: one folder per skill, each with a `SKILL.md`.
- `agents/`: the reviewer agents. Each one preloads its skill.
- `settings/settings.json`: shared settings (plugins, marketplaces, model, theme). No secrets.
- `install.sh`: links skills into `~/.claude/skills` and `~/.agents/skills` (Codex), and agent definitions into `~/.claude/agents`.
- `.claude/skills/setup-claude-code/`: the skill that runs the setup. It only exists while Claude is opened in this repo.

## Set up a new PC
```
git clone <repo-url>
cd <repo>
claude
```
Then say **"set up for Claude Code"**. Claude checks prerequisites, shows any conflicts with files already in `~/.claude`, links everything, merges the settings, and asks you to restart.

Use the SSH clone URL only if the PC has a GitHub key. HTTPS works if the repo is public.

## Install shared skills directly

```bash
./install.sh --dry-run
./install.sh                       # Claude and Codex (default)
./install.sh --target codex         # Codex skills only
./install.sh --target claude        # Claude skills and agents only
```

Options can be combined:

- `--target claude|codex|all`: choose which clients to update; defaults to `all`.
- `--dry-run`: print planned actions without writing anything.
- `--backup`: move conflicts into a unique installation directory under `~/.claude/backups/` or `~/.agents/backups/`, then create the links. Backups separate skills from agents.

Without `--backup`, conflicting files are preserved and the installer exits nonzero after processing the other entries. Filesystem errors stop the run immediately. Repeated runs preserve correct links. Cleanup removes only broken links into this repository in the selected clients' skill/agent directories.

Only directories containing `SKILL.md` are installed as skills. Codex supports these symlinks; restart it if new skills do not appear, then ask it to use a skill by name, for example `ansible-review`. See the [Codex skill documentation](https://learn.chatgpt.com/docs/build-skills).

The installer does not translate settings, register Claude agent definitions with Codex, or copy `CLAUDE.md`. Codex configuration belongs in `~/.codex/config.toml`, and global instructions in `~/.codex/AGENTS.md`. Some shared skills still refer to Claude-specific paths or tools; linking makes them discoverable but does not convert those instructions.

## Update
- `git pull`. Edited skills update right away, because they are links.
- Run the setup again when a skill or agent was added, or when you moved the repo folder. It is safe to repeat.

## Manual steps
- Log in to claude.ai so synced skills arrive. Remove the claude.ai copy of `product-brief`.
- Install `rust-analyzer` if you use the rust-analyzer plugin.
- Add MCP servers by hand. The repo holds none, because they use local binaries and secrets.

## Platforms
Linux and macOS. On Windows, use WSL. Native Windows needs Developer Mode for symlinks and is not supported.
