---
name: z2p-design
description: Use as zero-to-prod stage 6, after PLAN.md, to design how the parts fit together (e.g. "design the app", "write the design doc", "architecture and data model"). Writes DESIGN.md with flows, architecture, entities, database, interfaces, permissions, cross-cutting rules, folder layout, and decisions.
---

# Z2P Design (stage 6)

Turn `PLAN.md` and `REQUIREMENTS.md` into `DESIGN.md`, so code, tasks, and reviews follow one design. The data model is the most expensive thing to change later, so take it slowly. Read `~/.claude/skills/zero-to-prod/CONVENTIONS.md` first.

## Rules
- Follow the stack in `PLAN.md`. If the design needs a different one, stop and ask to change `PLAN.md` first.
- Cite requirement IDs (`R1`, `N1`), never repeat their text.
- The simplest design that meets the Must requirements. No extra layers.
- Plain English. Short sentences.

## Steps

1. **Read `PLAN.md` and `REQUIREMENTS.md`.** If `DESIGN.md` exists, update it.
2. **Write the 9 sections in this order.** Flows come first, because everything else serves them.
   1. **User flows:** each main journey, step by step. Each flow names the requirement IDs it covers. Every Must requirement is in at least one flow.
   2. **Architecture:** one Mermaid diagram with every part (frontend, backend, database, jobs, outside services), how they talk, and where each one runs. It must match the hosting in `PLAN.md`.
   3. **Entities:** what each one means in the domain, and how it relates to the others. Every entity named in `PLAN.md` appears.
   4. **Database:** run the `schema-design` skill and write its result into `## Database`. Write "no stored data" if there is none.
   5. **Interfaces:** pages or screens, API endpoints, or CLI commands. Each has input, output, and errors. Every flow step maps to an interface.
   6. **Auth and permissions:** a table of role × data × action. Skip only if there are no users. `web-security-review` checks the code against it later.
   7. **Cross-cutting:** config and secrets, error handling, migrations, logging.
   8. **Folder layout.**
   9. **Design decisions:** each with Choice, Why, Alternatives. If coach mode is on, follow the coach mode rules of `project-planner`.
3. **UI.** If there is a frontend, offer `impeccable` for the look and link its output. Do not design the look here.
4. **Gate check.** Every Must is in a flow. Every flow step has an interface. Every entity from `PLAN.md` is modelled. Every table has a grain and a primary key (or "no stored data"). The architecture says where each part runs. A permissions table exists if there are users. Fix what fails.
5. **Ask the user to confirm,** then add `Confirmed: <date>` under the title.

## Template

````markdown
# <Product name> - Design

Status: Draft | Date: YYYY-MM-DD | Confirmed: _(date, once you agree)_

## 1. User flows
### F1: <name> (R1, R2)
1. <step> -> <interface>

## 2. Architecture
```mermaid
flowchart LR
```
<Where each part runs.>

## 3. Entities
## 4. Database
## 5. Interfaces
| Interface | Input | Output | Errors | Flows |
|-----------|-------|--------|--------|-------|

## 6. Auth and permissions
| Role | Data | Action | Allowed |
|------|------|--------|---------|

## 7. Cross-cutting
## 8. Folder layout
## 9. Design decisions
### D1: <decision>
- **Choice:**
- **Why:**
- **Alternatives:**
````

## Hand-off
If `STATUS.md` exists, end with "Run `/clear`, then `zero-to-prod` for the next stage." Otherwise end with: "Next, use the plan-to-tasks skill."
