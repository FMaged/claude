---
name: zero-to-prod
description: Use to take a solo project from idea to production, one stage at a time (e.g. "zero to prod", "next stage", "where is my project", "start a new project the full way"). Finds the next stage from STATUS.md, runs it, checks its gate, and records the result.
---

# Zero to prod

The orchestrator of the chain. It finds the next stage, runs it, checks the gate from the files, and writes `STATUS.md`. The rules, stage table, gates, and `STATUS.md` format are in `CONVENTIONS.md` next to this file. Read it first.

You are the only thing that writes `STATUS.md`. Stage skills never do.

## 1. Find the state

- **No `STATUS.md`, folder empty:** start the project (see Start).
- **No `STATUS.md`, but files or code exist:** adopt the project (see Adopt in `CONVENTIONS.md`).
- **`STATUS.md` exists:** read it, then go to Next stage.

### Start
1. Run `git init` if this is not a git repo.
2. Write `STATUS.md` with every stage `todo` and stage 0 `done`.
3. Write a minimal `CLAUDE.md`: the project name, "Progress is in `STATUS.md`", and the list of stage files. Add nothing else.

## 2. Next stage

Pick the first stage that is not `done` or `skipped`. A `stale` stage comes first: re-check its gate before moving on.

- **Stage 1:** ask "Do you already have an idea?". If yes, mark it `skipped`.
- **A `waiting` stage:** ask whether the evidence has arrived. If not, say what it is waiting for and stop.
- **Stage 5:** ask "Fast or coach mode?". Coach mode means project-planner's coach mode.
- If the stage's skill is not installed, say so and offer to skip the stage.

Set the stage to `doing`, then run its skill from the stage table.

## 3. After the stage

1. Check the gate by reading the files, as `CONVENTIONS.md` lists it.
2. At gates 3, 4, 5, 6, and 9, also ask the user for a yes.
3. Write `STATUS.md`: state, gate result, date, note.
   - Gate passes: `done`.
   - Gate fails: keep `doing` and tell the user what is missing.
   - Stage 3 with `Decision: Change` or `Stop`: follow Going back in `CONVENTIONS.md`.
4. After stage 5 is `done`, add a line to `CLAUDE.md`: "Skills for this project: ..." with the skills that fit the chosen stack (for example `svelte`, `sql-writing`, `docker-review`).
5. End with: "Run `/clear`, then `zero-to-prod` again."

## Going back

If the user wants to reopen an earlier stage, or stage 10 sends items back, follow Going back in `CONVENTIONS.md`: mark later `done` stages `stale`, and re-check them before moving on.
