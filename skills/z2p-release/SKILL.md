---
name: z2p-release
description: Use as z2p stage 9, when the build is done, to check everything once more and release the MVP (e.g. "release the MVP", "are we ready to ship?", "final review before launch"). Checks tests, CI, every Must requirement, reviews, backups, and rollback, then writes RELEASE.md and asks for the user's yes.
---

# Z2P Release (stage 9)

The final proof before real users arrive. The release goes over the pipeline that the walking skeleton already built. Read `~/.claude/skills/z2p/CONVENTIONS.md` first.

## Rules
- Check, do not assume. Every line in `RELEASE.md` comes from something you ran or read.
- A failed Must requirement blocks the release, unless the user moves it to Later in `REQUIREMENTS.md`.
- Never release without the user's yes.
- Plain English. Short sentences.

## Steps

1. **Read.** `REQUIREMENTS.md`, `DESIGN.md`, `PLAN.md`, `TASKS.md`, and `RELEASE.md` (the Deploy and Rollback sections from `z2p-deploy`). If any MVP task is `[ ]`, stop and say so.
2. **Tests and CI.** Run the tests. Check that CI is green on `main`.
3. **Requirements table.** In `RELEASE.md`, one row per Must requirement: ID, each acceptance criterion, how you checked it, pass or fail. Run the check, do not copy the task notes. Also check each `N` requirement by the method it names.
4. **Reviews.** Detect the file types and run each matching review skill. Always run `web-security-review` against the permissions in `DESIGN.md`, and `sql-review` against its database section (skip the second if there is no stored data). Run the infra reviewers when those files exist.
5. **Findings.** List them by severity in `RELEASE.md`. Each high finding is either fixed (say how), or accepted by the user with a reason. Do not accept one on the user's behalf.
6. **Backups.** If there is data, set up backups and restore one into a scratch database or folder. Write the date and the result. Skip with "no stored data" otherwise.
7. **Deploy.** Deploy the MVP through the pipeline. Check that it works where users get it, and that the Rollback steps are still current. If they are not, use `z2p-deploy` to redo and try them.
8. **Release notes.** Write short notes for users in `RELEASE.md`: what is in, what is not (Later), known problems.
9. **Gate check.** Tests and CI green; every Must requirement checked; matching reviews run; no open high finding; MVP live and working; rollback tried; backup restored once if there is data. Fix what fails.
10. **Ask the user** for the go-ahead. On yes, add `Release: approved <date>` under the title. On no, list what blocks and stop.

## Template

````markdown
# <Product name> - Release

Release: _(approved YYYY-MM-DD, once you agree)_

## Deploy
_(from z2p-deploy)_

## Rollback
_(from z2p-deploy)_

## Requirements check
| ID | Criterion | How checked | Result |
|----|-----------|-------------|--------|

## Reviews
| Severity | Skill | File:line | Finding | Fixed / Accepted (reason) |
|----------|-------|-----------|---------|---------------------------|

## Backup
- **Set up:**
- **Restore tried on:**
- **Result:**

## Release notes
- **In:**
- **Not yet (Later):**
- **Known problems:**
````

## Hand-off
If `STATUS.md` exists, end with "Run `/clear`, then `z2p` for the next stage." Otherwise end with: "The MVP is released. Next, use the z2p-operate skill."
