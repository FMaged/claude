---
name: plan-to-tasks
description: Use when the user wants to turn PLAN.md into tasks or create TASKS.md (e.g. "convert the plan to tasks"). Also runs after project-planner. Writes TASKS.md split into stages; each task says what, why, and how.
---

# Plan to Tasks

Read `PLAN.md` and write `TASKS.md` next to it.

- Split the work into a few stages, each ending in something that works (e.g. Setup → Core → Features → Deploy).
- Keep tasks small and in the order they should be done.
- Only create tasks for what's in the plan. Don't add extra work.
- Keep each task short and concrete.

## In the chain
Read `DESIGN.md`, `REQUIREMENTS.md`, and `PLAN.md` if they exist.
- When `PLAN.md` names a host, Stage 1 is always the walking skeleton: hello world, a test runner, CI, and a deploy to production; error tracking; if there is a database, create it in production and run the first migration; try a rollback once. These tasks say "use z2p-deploy".
- After the skeleton, make tasks from the `DESIGN.md` tables, interfaces, and flows. Each task's How names the `DESIGN.md` section it builds and the requirement IDs it delivers.
- Check that every Must requirement is delivered by at least one task. Add a task for any that is not.
- If `STATUS.md` exists, end with the hand-off line from `~/.claude/skills/zero-to-prod/CONVENTIONS.md` instead of asking to start the first task.

## Format
```markdown
# <Project Name>: Tasks

## Stage 1: <title>

### [ ] T1.1: <title>
**What:** <what to build>
**Why:** <why it's needed>
**How:** <short concrete steps>
**Notes:** _(added after implementation if anything came up)_
```

When done, ask: "Start the first task?" If yes, use the `task-runner` skill.
