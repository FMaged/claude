---
name: project-planner
description: Use whenever the user wants to plan, design, or start a new project, app, or feature (e.g. "let's plan a project", "I want to build X"). Asks about every decision, then writes PLAN.md recording each decision and why.
---

# Project Planner

Interview the user, then write `PLAN.md` with every decision and its reason.

## Keep it simple
- Pick the simplest solution that meets the need. Prefer fewer tools, fewer services, fewer layers.
- Recommend boring, well-known tech the user already knows.
- Only plan what the MVP needs. Push everything else to "Later".
- No microservices, queues, caches, Docker, etc. unless there's a real reason now.
- Skip questions that don't apply to this project.

## Interview
Use `AskUserQuestion`, a few questions at a time. Put your recommended (simplest) option first and say why. Ask follow-ups when an answer raises new questions. If the user says "you decide", choose the simplest option and record that.

Cover what applies:
1. **Goal:** what it is, who it's for, the MVP features, what's out of scope
2. **Stack:** language, framework, database, auth, hosting
3. **Structure:** main data/entities, pages or endpoints, folder layout
4. **Workflow:** testing, how it gets deployed

Show a short summary of the decisions and confirm before writing.

## PLAN.md
```markdown
# <Project Name>

## Goal
<what it is and who it's for>

## MVP Features
- <feature>

## Later / Out of Scope
- <feature>

## Stack
| Part | Choice |
|------|--------|

## Structure
<entities, pages/endpoints, folder layout, as short as possible>

## Decisions
### D1: <decision>
- **Choice:** <what>
- **Why:** <reason>
- **Alternatives:** <what else was considered>
```

If a decision changes later, update it and add a "Changed: <why>" line to it.

When done, ask: "Convert this plan into tasks?" If yes, use the `plan-to-tasks` skill.
