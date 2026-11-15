---
name: bash
description: Use when writing or changing a Bash or shell script — an install or setup script, a CI job script, a Packer or cloud-init provisioner, a cron job — strict mode (set -euo pipefail) and where it bites, quoting and arrays, arguments with a usage line and --dry-run, exit codes, safe re-runs, temporary files removed by a trap, portability to macOS and Git Bash, scripts that run unattended, and shellcheck (e.g. "write a bash script that…", "add --dry-run to this script", "why does my script stop halfway with no error under set -e", "make this script work on macOS", "fix these shellcheck warnings"). For PowerShell, use powershell.
---

# Bash

A shell script is usually short, written once, and then run unattended for years, so
write it to stop at the first real failure, to survive any file name, to change nothing
under `--dry-run`, and to change nothing on a second run. Most shell trouble is an
unquoted variable, a failure that `set -e` did not catch, or a tool that behaves
differently on another machine.

For PowerShell, `powershell`. For the provisioner scripts of an image, also `packer`.
For comments, `code-comments`. The worked example is `evals/examples/bash/` in the skills
repo.

## 0. Bash or not, and which Bash

Bash is right for gluing commands together: install steps, a CI job, a provisioner, a
wrapper around one tool. Use Python instead when the script needs real data structures,
parses JSON beyond one `jq` call, does arithmetic on dates, or grows past about 200 lines.

| Where it runs | Shell | What to watch |
|---|---|---|
| Linux servers, CI runners, Packer guests | Bash 5 | Nothing special |
| macOS | `/bin/bash` is 3.2 | No `mapfile`, no `declare -A`, no `${var,,}` (section 6) |
| Git Bash on Windows | Bash 5 with MSYS paths | Symlinks, path forms, CRLF (section 6) |
| `#!/bin/sh`, cloud-init `runcmd` | `dash` on Debian and Ubuntu | Not Bash at all: no arrays, no `[[ ]]`, no `pipefail` in older dash |

Start a Bash script with `#!/usr/bin/env bash`, which finds a newer Bash where one is
installed. A script meant for `sh` is written for POSIX sh and checked with
`shellcheck --shell=sh`.

## 1. Strict mode, and where it bites

```bash
#!/usr/bin/env bash
# Installs one pinned tool from a release archive, checked against its SHA-256.
# Usage: fetch-tool.sh [--dry-run] [--dest DIR] NAME URL SHA256
set -euo pipefail
```

`-e` stops at a failed command, `-u` at an unset variable, and `pipefail` makes a pipeline
fail when any part of it fails. Each has holes; these are the ones that bite (all checked
in Bash 5.2):

- **`-e` is off inside a condition**: in `if`, `while`, and `until` tests, left of `&&`
  and `||`, after `!`, and in every function called from there. `if deploy; then` runs
  all of `deploy` without `-e`, so a failure in its middle goes unnoticed. Call it on its
  own line, then test something else.
- **`local var=$(cmd)` hides the failure** of `cmd`: the status is the one of `local`,
  which is 0. Split it: `local var; var=$(cmd)`.
- **A command substitution inside an argument** is not checked: `echo "id: $(get_id)"`
  carries on when `get_id` fails. Assign it to a variable first.
- **`pipefail` and an early reader.** `cmd | head -n 1` fails with 141 when `cmd` writes
  more than `head` reads, because `cmd` is killed by SIGPIPE. Read the first line another
  way (`read -r first < <(cmd)`), or let `head` read everything.
- **A command that fails on purpose.** `grep` exits 1 when it finds nothing, and
  `count=$(grep -c x file)` stops the script when the count is 0. `((count++))` returns 1
  when `count` was 0. Use `count=$((count + 1))`, and for `grep`, say what "nothing found"
  means: `if grep -q x file; then …`.
- **`|| true` only with a comment** that says why the failure does not matter. Without
  one, nobody can tell a deliberate skip from a hidden bug.
- **`-u` and optional values.** `${VAR:-}` for an optional environment variable, and
  `${1:-}` for an optional argument. In Bash before 4.4 (macOS), an empty array is
  "unbound" too: `"${args[@]+"${args[@]}"}"` expands it safely in every version.
- **To see a status without stopping**, capture it: `code=0; cmd || code=$?`.

`set -x` prints every command with its values expanded, secrets included. Turn it on
only around the lines you are debugging, never in a CI job that handles tokens.

## 2. Quoting

- **Quote every expansion**: `"$var"`, `"$(cmd)"`, `"${arr[@]}"`. An unquoted one is
  split on spaces and expanded as a glob, so a file called `my file` becomes two
  arguments, and `*` becomes the directory listing.
- **Arrays for argument lists**, never a string of options:

  ```bash
  args=(--fail --silent --show-error --location)
  [ "$dry" = 1 ] || args+=(--output "$file")
  curl "${args[@]}" "$url"
  ```

- `"$@"` passes the script's arguments on unchanged. `$*` and an unquoted `$@` do not.
- `printf '%s\n' "$var"`, not `echo "$var"`: `echo` treats a value of `-n` or `-e` as an
  option, and it differs between shells.
- `while IFS= read -r line; do …; done < file`, never `for line in $(cat file)`. For
  file names, `find … -print0` with `read -r -d ''`, which survives any name.
- `rm -- "$file"` and `./*` instead of `*`, so a file named `-rf` is a file.
- `local` for every variable in a function, `readonly` for constants, lower case for
  the script's own variables, upper case only for the environment.
- `$(cmd)`, not backticks. `[ … ]` with quotes works in every shell; `[[ … ]]` is Bash
  and is needed for `=~` and patterns. Pick one per script.

## 3. Arguments and output

```bash
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
```

- The usage line sits in the header comment and in `usage()`, and they match.
- Check every argument before the first change: a pattern for names that end up in
  paths, a format for hashes and versions, a scheme for URLs.
- **Exit codes:** 0 done (including "nothing to do"), 1 a problem, 2 wrong usage. Under
  `set -e`, a failed command ends the script with that command's own code: curl's 37,
  or `tar`'s 2, which a caller reads as wrong usage. Catch the failures the script
  reports: `curl … || die "could not download $url"`.
- **Errors and progress go to stderr**; stdout is for the result, so another script can
  use it. One short line per step a person would want to see.
- **`--dry-run` changes nothing.** The reads still run, so the dry run shows what would
  really change, not every possible change. Send every change through one place: either
  return early with a `would: …` line, or wrap each change:

  ```bash
  act() { if [ "$dry" = 1 ]; then printf 'would: %s\n' "$*"; else "$@"; fi; }
  act ln -s "$src" "$dest"
  ```

  `act` cannot wrap a redirection (`> file`) or a pipeline; put those in a function and
  wrap the function.

## 4. Safe to run twice

- **Check before changing**, and change only the difference: compare the link target
  before `ln -s`, the checksum before a download, the line before an append
  (`grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"`). A second run that
  finds everything in place says so and exits 0.
- **`rm -rf "${dir:?}/"`**: with `:?`, an empty or unset `dir` stops the script instead of
  deleting `/`. Same for any path built from a variable before a delete.
- **Temporary files** come from `mktemp`, with the trap set on the next line:

  ```bash
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  ```

  An `EXIT` trap runs on a normal exit, on a failure under `-e`, and on TERM, INT, and
  HUP (checked in Bash 5.2); nothing runs on `kill -9`. One trap per script: a second
  `trap … EXIT` replaces the first.
- **Write files whole.** Write to a temporary file in the same directory, then `mv` it
  over the old one. A rename on one file system is atomic, so a reader never sees half a
  file, and a failed run leaves the old file.
- `mkdir -p` and `install -m 0755` are safe to repeat; a plain `mkdir` or `ln -s` fails
  on the second run. `ln -sfn` repeats too, but replaces whatever is in the way, so
  compare first where that could be someone's own file.

## 5. Scripts that run unattended

CI jobs, cron jobs, Packer provisioners, and cloud-init scripts have no one to answer a
prompt and no one watching the output.

- **No prompts.** `DEBIAN_FRONTEND=noninteractive apt-get install -y …`;
  `ssh -o BatchMode=yes`; `GIT_TERMINAL_PROMPT=0`. On a first boot, cloud-init or
  unattended-upgrades may hold the apt lock: `apt-get -o DPkg::Lock::Timeout=600`.
- **Retry the network**, not everything:
  `curl --fail --silent --show-error --location --retry 5 --retry-connrefused`. Without
  `--fail`, an error page is saved as if it were the file.
- **Check what you download** against a pinned SHA-256 before using it. Never
  `curl … | bash`.
- **A log someone can read:** one line per step with what it acted on, errors with the
  value that was wrong. Not `set -x`.
- **Secrets** come from the environment, not from arguments, which show in `ps` and in
  the job log. A token for `curl` goes in a header file (`--header @file`) or a config
  file (`--config`), not on the command line.
- **cloud-init** runs `runcmd` as one `sh` script, not Bash. Put a Bash script in
  `write_files` and run it with `[bash, /path/to/script]`.
- Packer provisioners run as root through `execute_command`, and every one starts with
  `set -euo pipefail` (`packer`, section 6).

## 6. Portability

Only where the script must run on more than Linux. Say which systems it supports in the
header comment.

| Task | GNU (Linux) | BSD (macOS) | Works on both |
|---|---|---|---|
| Edit in place | `sed -i 's/a/b/' f` | `sed -i '' 's/a/b/' f` | `sed -i.bak 's/a/b/' f && rm f.bak` |
| Script's own folder | `readlink -f "$0"` | not in older macOS | `cd "$(dirname "$0")" && pwd -P` |
| Date arithmetic | `date -d '1 day ago'` | `date -v-1d` | Python, or avoid it |
| File size, time | `stat -c %s f` | `stat -f %z f` | `wc -c < f` for the size |
| SHA-256 | `sha256sum` | `shasum -a 256` | test with `command -v` |
| Time limit | `timeout` | `gtimeout` from coreutils | test with `command -v` |

- **Bash 3.2 on macOS** has no `mapfile` or `readarray`, no associative arrays, no
  `${var,,}` or `${var^^}`, no `;&` in `case`, no `wait -n`, and treats an empty array as
  unset under `-u` (section 1). Test there with `/bin/bash script.sh`.
- **Git Bash on Windows**: `ln -s` copies instead of linking unless
  `MSYS=winsymlinks:nativestrict` is set and Windows allows symlinks (Developer Mode, or
  an administrator shell). Arguments that look like paths are rewritten for Windows
  programs; `MSYS_NO_PATHCONV=1` turns that off for one call, and `cygpath -w` gives a
  Windows path when a program needs one. A script checked out with CRLF line endings fails
  with `$'\r': command not found`; `*.sh text eol=lf` in `.gitattributes` prevents it.

## 7. shellcheck

`shellcheck` must report nothing. It catches most of section 2 and much of section 1.

- Turn a warning off only on the line it is wrong about, with the reason:
  `# shellcheck disable=SC2016 # the backticks are literal text to match`. Never for a
  whole file or in a config.
- `bash -n script.sh` checks the syntax without running anything.
- A script for `sh`: `shellcheck --shell=sh`, which also flags Bash-only syntax.

## Before calling it done

```
shellcheck <script>
<script> --help                      # the usage line, exit 0
<script>                             # wrong usage: exit 2
<script> --dry-run <args>            # changes nothing; read every "would:" line
<script> <args>                      # the change
<script> <args>                      # a second run: nothing changes, exit 0
```

Run it once with a value that should fail (a wrong checksum, a missing file) and check
that it exits 1, says what was wrong, and leaves nothing behind. If the script must run on
macOS, run it with `/bin/bash` there too.
