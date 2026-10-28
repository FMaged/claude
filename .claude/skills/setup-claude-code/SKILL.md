---
name: setup-claude-code
description: Use when the user says "set up for Claude Code", "install my setup", or "set up this PC" in this repo. Links the repo's skills and agents into ~/.claude, merges the shared settings, and lists the manual steps.
---

# Set up Claude Code

Run from the repo root. Do the steps in order and stop to ask where a step says so.

1. **Prerequisites.** Check `git` and `bash` exist. Warn (do not stop) if `rust-analyzer` is missing: the rust-analyzer plugin needs it.
2. **Dry run.** Run `./install.sh --dry-run` and show the summary line.
3. **Conflicts.** For each `conflict:` line, show the difference between the existing file or folder and the repo one (`diff -r`). Ask whether to back it up and link, or skip it. Do not decide for the user.
4. **Install.** Run `./install.sh`, adding `--backup` if the user chose to back up any conflict. If they skipped some conflicts, say those stay unlinked.
5. **Settings.**
   - Copy `~/.claude/settings.json` to `~/.claude/settings.json.bak` (create the file as `{}` if it does not exist).
   - Merge `settings/settings.json` into it. Add keys that are missing. In nested objects (`enabledPlugins`, `extraKnownMarketplaces`) add the missing entries.
   - If a key already has a different value, show both and ask before changing it.
   - Never drop the user's other keys.
6. **Restart.** Ask the user to restart Claude Code so the plugins install and the skills load. After the restart, check that the skills and agents appear. If a plugin did not install, look up the current plugin install command and run it.
7. **Manual steps.** Tell the user what is left for them:
   - Log in to claude.ai so synced skills arrive. Remove the claude.ai copy of `product-brief`, since the repo has its own.
   - Add MCP servers by hand if wanted. The repo holds none.
