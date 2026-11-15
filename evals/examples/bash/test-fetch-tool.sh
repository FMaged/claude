#!/usr/bin/env bash
# Runs fetch-tool.sh against local archives: each mode once, a second run, and bad input.
# Usage: evals/examples/bash/test-fetch-tool.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
tool=$here/fetch-tool.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# expect <exit code> <description> <args...>: runs the tool and checks its exit code.
# The tool's temporary files go to $work/tmp, which must be empty afterwards.
expect() {
  local want=$1 what=$2 code=0
  shift 2
  TMPDIR=$work/tmp "$tool" "$@" >"$work/out" 2>&1 || code=$?
  if [ "$code" != "$want" ]; then
    fail "$what: exit $code, expected $want"
    sed 's/^/      /' "$work/out"
  elif [ -n "$(ls -A "$work/tmp")" ]; then
    fail "$what: left temporary files behind"
  else
    pass "$what"
  fi
}

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d ' ' -f 1
}

mkdir -p "$work/tmp" "$work/src/hello-1.0"
printf '#!/bin/sh\necho hello\n' >"$work/src/hello-1.0/hello"
chmod +x "$work/src/hello-1.0/hello"
tar -czf "$work/hello-1.0.tar.gz" -C "$work/src" hello-1.0
python3 -I -m zipfile -c "$work/hello-1.0.zip" "$work/src/hello-1.0" # zip is not everywhere; python3 is
url=file://$work/hello-1.0.tar.gz
sha=$(sha256 "$work/hello-1.0.tar.gz")
bin=$work/bin

expect 0 "--help" --help
expect 2 "missing arguments" hello "$url"
expect 2 "unknown option" --force hello "$url" "$sha"
expect 2 "a name with a slash" ../hello "$url" "$sha"
expect 2 "a URL over plain http" hello "http://example.com/x.tar.gz" "$sha"

expect 0 "--dry-run" --dry-run --dest "$bin" hello "$url" "$sha"
if [ -e "$bin" ]; then fail "--dry-run created $bin"; else pass "--dry-run changed nothing"; fi
if grep -q '^would: ' "$work/out"; then pass "--dry-run says what it would do"; else fail "--dry-run printed no would: line"; fi

expect 0 "install" --dest "$bin" hello "$url" "$sha"
if [ "$("$bin/hello")" = hello ]; then pass "the installed tool runs"; else fail "the installed tool does not run"; fi

before=$(ls -li "$bin/hello")
expect 0 "a second run" --dest "$bin" hello "$url" "$sha"
if grep -q '^ok: ' "$work/out" && [ "$(ls -li "$bin/hello")" = "$before" ]; then
  pass "a second run changed nothing"
else
  fail "a second run replaced the tool"
fi

wrong=$(printf '%064d' 0)
expect 1 "a wrong SHA-256" --dest "$work/bin2" hello "$url" "$wrong"
if [ -e "$work/bin2/hello" ]; then fail "a wrong SHA-256 installed the tool"; else pass "a wrong SHA-256 installed nothing"; fi

expect 1 "a missing file" --dest "$work/bin3" hello "file://$work/nope.tar.gz" "$sha"

zip_sha=$(sha256 "$work/hello-1.0.zip")
expect 0 "install from a zip" --dest "$work/bin4" hello "file://$work/hello-1.0.zip" "$zip_sha"
if [ "$("$work/bin4/hello")" = hello ]; then pass "the tool from the zip runs"; else fail "the tool from the zip does not run"; fi

printf 'failures: %s\n' "$fails"
[ "$fails" = 0 ]
