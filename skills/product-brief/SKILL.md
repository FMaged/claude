---
name: "product-brief"
description: "Write a short product brief (PRODUCT_BRIEF.md) for a new idea: problem, users, first version, success, risks. Use before any planning or code, or to decide if an idea is worth building."
---

# Product brief

A product brief is a short document (1-2 pages). It answers five questions:

1. What problem do we solve?
2. Who has this problem?
3. What do we build first?
4. How do we know it worked?
5. What could go wrong?

It comes before any planning or code. Its main job is to help the user decide: build it, change it, or stop.

## Rules

- Problem first. Do not start with features or tech.
- Keep it short. Max about 2 pages. If it gets longer, it is turning into a requirements document (PRD), which is a later step.
- Plain English. Short sentences. Explain any technical word.
- Separate facts from guesses. Every guess is marked `[Assumption]`.
- Be honest. If the idea is weak, say so and give the reasons. Do not flatter.
- No tech stack, architecture, or task list. Those belong in the planning step (project-planner skill).
- Every researched fact (competitor, price, number) gets a source link.
- Write in English unless the user asks for another language.

## Steps

1. **Read what you have.** Read the user's idea, notes, and files. If `IDEA.md` exists, read it and do not ask again what it answers. If a `PRODUCT_BRIEF.md` already exists, update it instead of starting a new one.
2. **Find the gaps.** Ask for missing information. Ask at most 5 questions at a time, most important first. The key questions:
   - What problem? Who has it? Give one real example.
   - How do people solve it today? Why is that not good enough?
   - Why now? What changed?
   - What is the smallest first version that still solves the main problem?
   - How will we know it worked? (1-3 signs we can measure)
   - What is the biggest risk or guess?
   If the user says "just write it", fill the gaps yourself and mark each one `[Assumption]`.
3. **Check alternatives.** If web search is available, find 2-4 existing products or workarounds. Add source links. If search is not available, list them as assumptions to check.
4. **Write `PRODUCT_BRIEF.md`** with the template below.
5. **Check it** with the checklist below. Fix what fails.
6. **Give a verdict** in the chat: Go, Change, or Stop, with 1-3 reasons. Then name the next step (see Hand-off).

## Template

```markdown
# <Product name> - Product brief

Status: Draft | Date: YYYY-MM-DD | Owner: <name>

## 1. Problem
<Who has which problem, in 2-4 sentences. Include one real example.>

## 2. Target users
- Main user: <who uses it>
- Buyer: <who pays, if different>

## 3. How they solve it today
<Current tools or workarounds, and why they are not good enough.>

## 4. Our idea
<The solution in 3-5 sentences. Describe what changes for the user, not the tech.>

## 5. Why now
<What changed that makes this possible or needed now.>

## 6. First version (MVP)
In scope:
- <...>

Out of scope (not now):
- <...>

## 7. Success
We know it works when (1-3 measurable signs):
- <...>

## 8. Alternatives and competitors
| Name | What they do | How we are different | Source |
|------|--------------|----------------------|--------|

## 9. Risks and assumptions
| Assumption | Why it matters | How to test it |
|------------|----------------|----------------|

Riskiest assumption: <which one, and why>

## 10. Open questions
- <...>

## 11. Decision
Go / Change / Stop - <reason>.
Next step: <...>
```

## Checklist

- Can someone outside the project understand it in 3 minutes?
- Is the problem described without naming the solution?
- Does the first version have an "out of scope" list?
- Are the success signs measurable (a number, or a clear yes/no)?
- Is every guess marked `[Assumption]`?
- Does every researched fact have a source link?
- Is it free of tech stack and tasks?

## Hand-off

If `STATUS.md` exists, this skill is part of the z2p chain: end with "Run `/clear`, then `z2p` for the next stage." Your Go/Change/Stop verdict is the call; there is no separate validation stage. Outside the chain, use the list below.

- **Go:** First test the riskiest assumption with real people (talk to 5-10 target users, or show them a simple mockup). Update the brief with what you learn. Then use the project-planner skill to turn the brief into `PLAN.md` and `TASKS.md`.
- **Change:** Update the brief and run this skill again.
- **Stop:** Keep the brief. Write one line on why you stopped. It is useful later.