---
name: z2p-requirements
description: Use as z2p stage 4, after the brief, to write what the product must do and how well (e.g. "write the requirements", "what are the acceptance criteria"). Writes REQUIREMENTS.md with roles, requirements and testable acceptance criteria, non-functional requirements, and constraints.
---

# Z2P Requirements (stage 4)

Turn the brief into `REQUIREMENTS.md`: the contract that design, tasks, tests, and the release are checked against. Read `~/.claude/skills/z2p/CONVENTIONS.md` first.

## Rules
- Say **what** and **how well**, never **with what**. No stack, no architecture. That is stage 5.
- Every criterion is a yes/no check that can become a test.
- Plain English. Short sentences.
- Requirement IDs are the shared reference for later files, so never renumber after they are confirmed. Add new IDs at the end.

## Steps

1. **Read `PRODUCT_BRIEF.md`** (users, MVP scope, success signs). If `REQUIREMENTS.md` exists, update it.
2. **Users and roles.** One row per role with what they need.
3. **Functional requirements.** One heading each:
   - ID (`R1`, ...), priority (`Must` for the MVP, or `Later`).
   - User story: "As a <role>, I can <action>, so that <benefit>."
   - Acceptance: a checklist of yes/no checks (`- [ ] ...`).
   
   Every MVP item in the brief gets at least one Must requirement. Anything else goes to Later.
4. **Push back** on criteria that cannot be tested ("fast", "easy", "secure"). Ask for a number or a yes/no check instead.
5. **Non-functional requirements.** Go through every topic: performance, availability, security, privacy and personal data, accessibility, platforms and devices, data retention and backup, scale, cost, compliance. Answer each one or mark it "not needed" with a reason. Each answer has an ID (`N1`, ...) and says how it will be checked. If the product stores personal data, privacy law (GDPR in the EU) is never "not needed".
6. **Constraints, out of scope, open questions.**
7. **Gate check.** Every MVP item has a requirement. Every Must has acceptance criteria. Every topic is answered or marked "not needed". Fix what fails.
8. **Ask the user to confirm,** then put `Confirmed: <date>` in the status line.

Ask with `AskUserQuestion`, a few questions at a time, the simplest option first. If the user says "you decide", take the simplest option and mark it as a decision they can change.

## Template

```markdown
# <Product name> - Requirements

Status: Draft | Date: YYYY-MM-DD | Confirmed: _(date, once you agree)_

## Users and roles
| Role | Who | What they need |
|------|-----|----------------|

## Functional requirements

#### R1: <short name> (Must)
As a <role>, I can <action>, so that <benefit>.
Acceptance:
- [ ] <yes/no check>

## Non-functional requirements
| ID | Topic | Requirement | How we check it |
|----|-------|-------------|-----------------|
| N1 | Performance | ... | ... |

## Constraints
- <budget, deadline, required tech, skills>

## Out of scope
- <...>

## Open questions
- <...>
```

## Hand-off
If `STATUS.md` exists, end with "Run `/clear`, then `z2p` for the next stage." Otherwise end with: "Next, use the project-planner skill."
