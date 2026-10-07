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
