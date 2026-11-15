#!/usr/bin/env bash
# Links shared skills into Claude and Codex; agent definitions stay with Claude.
# Usage: ./install.sh [--target claude|codex|all] [--dry-run] [--backup] [--skip NAME]...
set -euo pipefail

dry=0
backup=0
target=all
skip=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --backup) backup=1 ;;
    --skip)
      [ "$#" -ge 2 ] || { echo "--skip requires a skill or agent name" >&2; exit 2; }
      skip+=("$2")
      shift
      ;;
    --target)
      [ "$#" -ge 2 ] || { echo "--target requires claude, codex, or all" >&2; exit 2; }
      target=$2
      shift
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$target" in
  claude|codex|all) ;;
  *) echo "Unknown target: $target (expected claude, codex, or all)" >&2; exit 2 ;;
esac

repo=$(cd "$(dirname "$0")" && pwd -P)
linked=0 ok=0 conflicts=0 removed=0 skipped=0

act() {
  if [ "$dry" = 1 ]; then echo "would: $*"; else "$@"; fi
}

# An agent can be named with or without its .md.
skipped_by_user() {
  local base name
  base=$(basename "$1")
  for name in "${skip[@]+"${skip[@]}"}"; do
    if [ "$name" = "$base" ] || [ "$name.md" = "$base" ]; then return 0; fi
  done
  return 1
}

link_item() {
  local src=$1 dest=$2 kind=$3
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    ok=$((ok + 1))
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    if skipped_by_user "$dest"; then
      echo "skip: $dest"
      skipped=$((skipped + 1))
    elif [ "$backup" = 1 ]; then
      if [ -z "$backup_dir" ]; then
        if [ "$dry" = 1 ]; then
          backup_dir="$root/backups/install-DRY-RUN"
        else
          mkdir -p "$root/backups"
          backup_dir=$(mktemp -d "$root/backups/install-XXXXXXXX")
        fi
      fi
      echo "backup: $dest -> $backup_dir/$kind/"
      act mkdir -p "$backup_dir/$kind"
      act mv "$dest" "$backup_dir/$kind/"
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

prune_links() {
  local directory=$1 dest link_target
  for dest in "$directory"/*; do
    [ -L "$dest" ] || continue
    link_target=$(readlink "$dest")
    case "$link_target" in
      "$repo"/*)
        if [ ! -e "$link_target" ]; then
          echo "remove: $dest (target is gone)"
          act rm "$dest"
          removed=$((removed + 1))
        fi
        ;;
    esac
  done
}

for client in claude codex; do
  [ "$target" = all ] || [ "$target" = "$client" ] || continue
  case "$client" in
    claude) root="$HOME/.claude" ;;
    codex) root="$HOME/.agents" ;;
  esac
  backup_dir=
  echo "Installing for $client"
  act mkdir -p "$root/skills"

  for src in "$repo"/skills/*/; do
    [ -f "$src/SKILL.md" ] || continue
    src=${src%/}
    link_item "$src" "$root/skills/$(basename "$src")" skills
  done

  if [ "$client" = claude ]; then
    act mkdir -p "$root/agents"
    for src in "$repo"/agents/*.md; do
      [ -f "$src" ] || continue
      link_item "$src" "$root/agents/$(basename "$src")" agents
    done
    prune_links "$root/agents"
  fi
  prune_links "$root/skills"
done

echo "Summary: linked $linked, already OK $ok, conflicts $conflicts, removed $removed, skipped $skipped"
[ "$conflicts" = 0 ]
