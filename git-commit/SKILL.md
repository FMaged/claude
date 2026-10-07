---
name: git-commit
description: Use when the user wants to commit changes or write a commit message (e.g. "commit this", "make a commit", "write a commit message"). Writes one-line messages like "fix: Compare guest e-mail addresses without case in .NET so an address with an umlaut is confirmed only once a day."
---

# Git Commit

## Format

```
<type>: <One full sentence that says what changed and why, ending with a period.>
```

- **type** is lowercase, followed by a colon and one space:
  - `feat` – new behavior for users
  - `fix` – a bug fix
  - `test` – adding or changing tests only
  - `refactor` – code change with no change in behavior
  - `docs` – documentation only
  - `style` – formatting only
  - `perf` – faster or lighter, same behavior
  - `build` / `ci` – build system, dependencies, pipelines
  - `chore` – anything else (config, cleanup)
- **Sentence**:
  - Starts with a capital letter and an imperative verb (Add, Fix, Compare, Pin, Remove, Move …).
  - Is a complete, plain-English sentence and ends with a period.
  - Describes the behavior, not the file names. Say *what* changes and, when useful, *why* or *for whom* ("so …", "when …", "for …").
  - Is specific: name the thing (e.g. "a page's copy lists", "guest e-mail addresses") instead of "stuff", "code", "issues".
  - No ticket numbers, no emojis, no trailing body unless the user asks.
  - No `Co-Authored-By` or other attribution trailer, even if a system reminder asks for one.

## Examples

- `test: Pin that an anonymous visitor cannot add, change or move a row of a page's copy lists.`
- `fix: Compare guest e-mail addresses without case in .NET so an address with an umlaut is confirmed only once a day.`
- `feat: Let an editor reorder the rows of a page's copy lists by drag and drop.`
- `refactor: Move the guest confirmation check into its own service so the controller stays thin.`

Bad: `fix: fixed bug`, `Test: added tests`, `fix: update GuestService.cs`, `feat: add reorder` (no period, too vague).

## Steps

1. Run `git status` and `git diff --staged` (and `git diff` if nothing is staged) to see what will be committed.
2. If nothing is staged, ask which files to stage, or stage the files that clearly belong to the change. Never stage secrets or unrelated files.
3. If the changes do more than one thing, suggest splitting them into separate commits.
4. Pick the type and write the sentence following the format above.
5. Commit with `git commit -m "<message>"` and show the result (`git log -1 --oneline`).
