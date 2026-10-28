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

## In the chain
If `STATUS.md` exists, this skill is stage 5 of zero-to-prod (see `~/.claude/skills/zero-to-prod/CONVENTIONS.md`).
- Read `IDEA.md`, `PRODUCT_BRIEF.md`, `VALIDATION.md`, and `REQUIREMENTS.md` if they exist. Do not ask again what they answer.
- If `REQUIREMENTS.md` exists, list the MVP features by requirement ID (`R1`, `R2`, ...) instead of asking for them again. Use its non-functional requirements (`N1`, ...) to choose the stack.
- Always ask about hosting and the database engine (or "no database").
- Keep Structure to one line per main entity and page. The detail goes in `DESIGN.md`.
- After the user confirms, add `Confirmed: <date>` under the title. The gate checks for it.
- End with the hand-off line from `CONVENTIONS.md` instead of asking to convert the plan.

## Interview
Use `AskUserQuestion`, a few questions at a time. Put your recommended (simplest) option first and say why. Ask follow-ups when an answer raises new questions. If the user says "you decide", choose the simplest option and record that.

Cover what applies:
1. **Goal:** what it is, who it's for, the MVP features, what's out of scope
2. **Stack:** language, framework, database, auth, hosting
3. **Structure:** main data/entities, pages or endpoints, folder layout
4. **Workflow:** testing, how it gets deployed

Show a short summary of the decisions and confirm before writing.

## Coach mode
Turned on by "coach me" or "teach me", or when the orchestrator says so at stage 5. The goal is that the user learns why each choice is best. Other skills (`z2p-design`, `z2p-deploy`) can say "use project-planner's coach mode" and follow these rules.
- **Question text:** say why the recommended option is best, and when it would be the wrong choice.
- **Option descriptions:** say what that option costs.
- **When the user argues back:** answer the objection honestly. If their argument is right, change the recommendation and say so. Then continue.
- **PLAN.md:** record the final reasoning in each decision's Why and Alternatives.

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
