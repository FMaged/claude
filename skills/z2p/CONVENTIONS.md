# z2p conventions

The rules every stage of the chain follows. The orchestrator (`z2p`) and every stage skill read this file. Stage skills find it in the `z2p` folder of the skills directory they were loaded from (`~/.claude/skills/z2p/` for Claude Code, `~/.agents/skills/z2p/` for Codex).

## Stages

| Stage | Skill | Writes | Gate (checked from the files) | User yes |
|-------|-------|--------|-------------------------------|----------|
| 0 Start | `z2p` | `STATUS.md`, `CLAUDE.md` | Git repo, `STATUS.md`, and `CLAUDE.md` exist | no |
| 1 Idea (optional) | `z2p-idea` | `IDEA.md` | One problem and one target user named, or stage skipped because the user brought an idea | no |
| 2 Brief | `product-brief` | `PRODUCT_BRIEF.md` | All sections filled; `Riskiest assumption:` line is filled | no |
| 3 Validate | `z2p-validate` | `VALIDATION.md` | Every risky assumption has a verdict (`held`, `failed`, or `untested`); a `Decision: Go`, `Change`, or `Stop` line with a reason; `Confirmed: <date>` in the date line | **yes** |
| 4 Requirements | `z2p-requirements` | `REQUIREMENTS.md` | Every MVP item in the brief has at least one requirement; every Must requirement has acceptance criteria; every non-functional topic is answered or marked "not needed"; `Confirmed: <date>` in the status line | **yes** |
| 5 Plan | `project-planner` | `PLAN.md` | MVP lists requirement IDs; a Later section exists; stack names a database engine (or "no database") and hosting; main entities named; every decision has Choice, Why, Alternatives; `Confirmed: <date>` under the title | **yes** |
| 6 Design | `z2p-design` (+ `schema-design`) | `DESIGN.md` | Every Must requirement is in a flow; every flow step maps to an interface; every entity from `PLAN.md` is modelled; every table has a grain and a primary key (or "no stored data"); architecture says where each part runs; a permissions table exists if there are users; `Confirmed: <date>` under the title | **yes** |
| 7 Tasks | `plan-to-tasks` | `TASKS.md` | Stage 1 is the walking skeleton, unless `PLAN.md` says there is nothing to deploy; every task has What, Why, How; every Must requirement is delivered by at least one task | no |
| 8 Build | `task-runner` | code, `TASKS.md` notes | All MVP tasks are `[x]`; tests pass | no |
| 9 Release | `z2p-release` | `RELEASE.md` | Tests and CI green; every Must requirement's acceptance criteria checked; matching reviews run; no open high findings; MVP live where users get it and works; rollback tried; backup restored once if there is data; `Release: approved` line | **yes** |
| 10 Operate | `z2p-operate` | `BACKLOG.md` | Errors and uptime visible; an alert reached the user; backlog started | no |

A gate with "user yes" is not passed by the files alone. The orchestrator asks, unless the stage skill got the yes in this run, and records the answer.

## STATUS.md

Written only by `z2p`. One table, one line per stage, plus a cycle counter.

```markdown
# <Project name>: Status

Cycle: 1

| Stage | State | Gate | Date | Note |
|-------|-------|------|------|------|
| 0 Start | done | pass | 2026-10-28 | |
| 1 Idea | skipped | n/a | 2026-10-28 | user brought an idea |
| 2 Brief | doing | | 2026-10-28 | |
```

- **State:** `todo`, `doing`, `waiting` (the note says why, like "waiting for 3 interviews"), `done`, `skipped`, `stale`.
- **Gate:** `pass`, `fail: <what is missing>`, or `n/a`. Empty until checked.
- **Date:** the date the state last changed (YYYY-MM-DD).
- **Cycle:** starts at 1. It goes up by 1 each time stage 10 sends backlog items back into the chain.

## Going back

- **Stage 3 decides:** `Decision: Stop` ends the project; keep the brief and the validation, mark stage 3 `done`, and mark the later stages `skipped` with the note "stopped at validation". `Decision: Change` reopens stage 2 with the note saying what to change, and sets stage 3 to `todo` so it runs again on the changed brief. `Decision: Go` passes the gate.
- **Reopening a stage:** set it to `doing`. Every later stage that is `done` becomes `stale`. Before moving on, the orchestrator re-checks the gate of each stale stage. A passing gate returns it to `done`. A failing gate returns it to `todo`.
- **Reopening a stopped project** (stage 2 or 3 after `Decision: Stop`): every stage with the note "stopped at validation" goes back to `todo`. A stage skipped for another reason, like stage 1 when the user brought an idea, stays `skipped`.
- **Stage 10 backlog:** picked items go to stage 7. An item that adds a requirement goes to stage 4 instead. An item that changes the plan goes to stage 5. Cycle goes up by 1. `BACKLOG.md` marks each picked item with that cycle; the stage it goes to works on those items and keeps what earlier cycles wrote in its file.

## Adopt mode

If there is no `STATUS.md` but the folder has files or code:
1. Check the gates of stages 1 to 10 from the files that exist. Stage 0 is set up in step 3, not checked.
2. Show the user a table: stage, gate result, proposed state.
3. After the user confirms, do the Start steps of `z2p` that are missing and change no other file: `git init` if this is not a git repo, and a `CLAUDE.md` if there is none (an existing one keeps its text and gets the `STATUS.md` line and the list of stage files). Then write `STATUS.md` with stage 0 and the passing stages as `done` and the rest as `todo`. Stages with a "user yes" gate need the user's yes now too.

## Rules for stage skills

1. Read the previous stage's file if it exists. Ask only for what is missing.
2. Write one file, with the name from the stage table.
3. Never create or edit `STATUS.md`. That keeps every stage skill usable alone.
4. Hand-off line: if `STATUS.md` exists in the project, end with "Run `/clear`, then `z2p` for the next stage." Do not name the next skill. If there is no `STATUS.md`, end with the skill's own hand-off.
5. Requirement IDs (`R1`, `N1`) from `REQUIREMENTS.md` are the shared reference. Later files cite them instead of repeating the text.
6. Confirmation line: when the user confirms a file at a "user yes" gate, add `Confirmed: <date>` as the file says (title area or status line).
