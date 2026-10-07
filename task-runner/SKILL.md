---
name: task-runner
description: Use when the user wants to implement tasks from TASKS.md (e.g. "next task", "implement T1.2", "continue"). Implements a task, adds notes, and marks it complete.
---

# Task Runner

1. Pick the task the user named, or the first unchecked `[ ]` task in TASKS.md.
2. Implement it following its What/How and the decisions in PLAN.md. Write the simplest code that works. No extra features or abstractions.
3. Check that it works (run it, or run the tests).
4. If anything came up (a change from the plan, a problem, a decision), write it in the task's **Notes**. Otherwise leave Notes as is.
5. Mark it done: `### [ ]` → `### [x]`. Only do this once it works.
6. If a PLAN.md decision had to change, ask the user first, then update PLAN.md with the reason.
7. Give a short summary and ask whether to continue.
