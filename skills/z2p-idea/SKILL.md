---
name: z2p-idea
description: Use as z2p stage 1, when the user has no idea yet or wants help finding a problem worth solving (e.g. "I want to build something but don't know what", "help me find an idea"). Interviews, then writes IDEA.md with one problem and one target user.
---

# Z2P Idea (stage 1)

Help the user find one problem worth solving, and write `IDEA.md`. Read `~/.claude/skills/z2p/CONVENTIONS.md` first. This stage is optional: a user who already has an idea skips it.

## Rules
- Problem first. No features, no tech.
- Plain English. Short sentences.
- Mark every guess `[Assumption]`.
- Be honest. A problem nobody has is not worth building for.

## Steps

1. **Read what exists.** If `IDEA.md` exists, update it instead of starting over.
2. **Interview.** Use `AskUserQuestion`, at most 4 questions at a time. Cover:
   - **Frustrations:** what annoyed you this month? What do you do by hand that a computer could do?
   - **Skills:** what can you build, or learn quickly?
   - **Interests:** what do you know well enough to judge a tool for it?
   - **People you can reach:** who could you talk to this week? Name roles or places, not "everyone".
3. **List 3 to 5 candidate problems.** One line each: who has it, and how they cope today.
4. **Narrow to one.** Recommend one and say why (a real pain, reachable people, buildable by one person). Let the user pick. Name one target user.
5. **Write `IDEA.md`** with the template below.
6. **Check:** one problem and one target user are named, and the problem does not name a solution. Fix what fails.

## Template

```markdown
# <Working name> - Idea

Date: YYYY-MM-DD | Owner: <name>

## Problem
<One problem, 2-3 sentences, without naming a solution.>

## Target user
<One kind of person, and where to find them.>

## How they cope today
<Current workaround.>

## People I can reach
- <role or place, and how>

## My skills and interests
- <...>

## Other candidates (not chosen)
| Problem | Why not now |
|---------|-------------|

## Assumptions
- [Assumption] <...>
```

## Hand-off
If `STATUS.md` exists, end with "Run `/clear`, then `z2p` for the next stage." Otherwise end with: "Next, use the product-brief skill."
