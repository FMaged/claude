#!/usr/bin/env bash
# Installs one pinned tool from a release archive, checked against its SHA-256.
# Usage: fetch-tool.sh [--dry-run] [--dest DIR] NAME URL SHA256
# The archive is a .zip, a .tar.gz, or the program itself, and holds one file named NAME.
# Safe to run again: a tool already installed from the same SHA-256 is left alone.
# Runs on Linux and macOS. Writing to the default /usr/local/bin needs root.
set -euo pipefail

usage() { printf 'Usage: %s [--dry-run] [--dest DIR] NAME URL SHA256\n' "${0##*/}" >&2; }
die() { printf '%s: %s\n' "${0##*/}" "$1" >&2; exit "${2:-1}"; }

dry=0
dest=/usr/local/bin
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --dest)
      [ "$#" -ge 2 ] || die "--dest needs a directory" 2
      dest=$2
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    -*) usage; die "unknown option: $1" 2 ;;
    *) break ;;
  esac
  shift
done
[ "$#" -eq 3 ] || { usage; exit 2; }
readonly name=$1 url=$2 sha=$3

case "$name" in
  '' | *[!A-Za-z0-9._-]* | .*) die "NAME must be letters, digits, dots, dashes, or underscores: $name" 2 ;;
esac
[[ $sha =~ ^[0-9a-f]{64}$ ]] || die "SHA256 must be 64 lower-case hex digits: $sha" 2
case "$url" in
  https://* | file://*) ;;
  *) die "URL must start with https:// (file:// for tests): $url" 2 ;;
esac

target=$dest/$name
stamp=$dest/.$name.sha256
if [ -x "$target" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sha" ]; then
  printf 'ok: %s is already the pinned build\n' "$target" >&2
  exit 0
fi
if [ "$dry" = 1 ]; then
  printf 'would: download %s, check its SHA-256, and install %s\n' "$url" "$target" >&2
  exit 0
fi

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d ' ' -f 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf 'download: %s\n' "$url" >&2
# Under set -e a failure would end the script with curl's or tar's own code (tar uses 2,
# which means wrong usage here), so these report it as 1.
curl --fail --silent --show-error --location --retry 5 --retry-connrefused --output "$work/download" "$url" ||
  die "could not download $url"
actual=$(sha256 "$work/download")
[ "$actual" = "$sha" ] || die "$url has SHA-256 $actual, expected $sha"

mkdir "$work/files"
case "$url" in
  *.zip) unzip -q "$work/download" -d "$work/files" || die "could not unpack $url" ;;
  *.tar.gz | *.tgz) tar -xzf "$work/download" -C "$work/files" || die "could not unpack $url" ;;
  *) cp "$work/download" "$work/files/$name" ;;
esac

binary='' count=0
while IFS= read -r -d '' file; do
  binary=$file
  count=$((count + 1))
done < <(find "$work/files" -type f -name "$name" -print0)
[ "$count" = 1 ] || die "expected one file named $name in $url, found $count"

mkdir -p "$dest"
install -m 0755 "$binary" "$dest/.$name.new"
mv -f "$dest/.$name.new" "$target" # a rename, so nothing ever runs a half-written file
printf '%s\n' "$sha" >"$stamp"
printf 'installed: %s\n' "$target" >&2
