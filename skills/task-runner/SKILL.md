---
name: task-runner
description: Use when the user wants to implement tasks from TASKS.md (e.g. "next task", "implement T1.2", "continue"). Implements a task, adds notes, and marks it complete.
---

# Task Runner

1. Pick the task the user named, or the first unchecked `[ ]` task in TASKS.md.
2. Implement it following its What/How, `DESIGN.md` (if it exists), and the decisions in PLAN.md. Write the simplest code that works. No extra features or abstractions.
3. If the project has a test setup, write or update tests with the task. Turn the acceptance criteria of the requirements the task delivers (see `REQUIREMENTS.md`) into tests. Check that it works (run it, or run the tests).
4. If anything came up (a change from the plan, a problem, a decision), write it in the task's **Notes**. Otherwise leave Notes as is.
5. Mark it done: `### [ ]` → `### [x]`. Only do this once it works.
6. If a PLAN.md or DESIGN.md decision had to change, ask the user first, then update the file with a "Changed: <why>" line.
7. When the last task of a TASKS.md stage is done, run the review skills that match the files changed in that stage (`sql-review` for SQL, `svelte-review` for Svelte, `docker-review` for Dockerfiles, and so on). Fix high findings now, or add them as tasks.
8. Give a short summary. If `STATUS.md` exists, end with the hand-off line from `~/.claude/skills/z2p/CONVENTIONS.md` and do not write `STATUS.md`. Otherwise ask whether to continue.
