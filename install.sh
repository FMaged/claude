#!/usr/bin/env bash
# Links skills/* and agents/*.md from this repo into ~/.claude.
# Usage: ./install.sh [--dry-run] [--backup]
set -u

dry=0
backup=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    --backup) backup=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

repo=$(cd "$(dirname "$0")" && pwd -P)
claude="$HOME/.claude"
backup_dir="$claude/backups/install-$(date +%Y%m%d-%H%M%S)"
linked=0 ok=0 conflicts=0 removed=0

act() {
  if [ "$dry" = 1 ]; then echo "would: $*"; else "$@"; fi
}

link_item() {
  src=$1 dest=$2
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    ok=$((ok + 1))
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$backup" = 1 ]; then
      echo "backup: $dest -> $backup_dir/"
      act mkdir -p "$backup_dir"
      act mv "$dest" "$backup_dir/"
      echo "link: $dest"
      act ln -s "$src" "$dest"
      linked=$((linked + 1))
    else
      echo "conflict: $dest exists and is not a link to this repo"
      conflicts=$((conflicts + 1))
    fi
  else
    echo "link: $dest"
    act ln -s "$src" "$dest"
    linked=$((linked + 1))
  fi
}

act mkdir -p "$claude/skills" "$claude/agents"

for src in "$repo"/skills/*/; do
  [ -d "$src" ] || continue
  src=${src%/}
  link_item "$src" "$claude/skills/$(basename "$src")"
done

for src in "$repo"/agents/*.md; do
  [ -f "$src" ] || continue
  link_item "$src" "$claude/agents/$(basename "$src")"
done

# Remove links into this repo whose target was deleted.
for dest in "$claude"/skills/* "$claude"/agents/*; do
  [ -L "$dest" ] || continue
  target=$(readlink "$dest")
  case "$target" in
    "$repo"/*)
      if [ ! -e "$target" ]; then
        echo "remove: $dest (target is gone)"
        act rm "$dest"
        removed=$((removed + 1))
      fi
      ;;
  esac
done

echo "Summary: linked $linked, already OK $ok, conflicts $conflicts, removed $removed"
[ "$conflicts" = 0 ]
