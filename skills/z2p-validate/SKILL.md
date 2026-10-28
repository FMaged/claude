---
name: z2p-validate
description: Use as zero-to-prod stage 3, after the product brief, to test its risky assumptions before any planning or code (e.g. "validate my idea", "is this worth building?"). Writes VALIDATION.md with a test plan, the evidence, and a Go, Change, or Stop decision.
---

# Z2P Validate (stage 3)

Test the brief's risky assumptions with the cheapest real evidence, and make the go/no-go call. This stage owns the decision; the brief's verdict was only a first opinion. Read `~/.claude/skills/zero-to-prod/CONVENTIONS.md` first.

## Rules
- Decide what counts as go and what counts as stop **before** the test runs. Write it down first.
- Evidence beats opinion. A friend saying "nice idea" is not evidence.
- Say so plainly when evidence is weak. Do not flatter.
- An assumption with no test is marked `untested`, never quietly dropped.
- Every researched fact gets a source link.

## Steps

1. **Read `PRODUCT_BRIEF.md`**, especially the Risks and assumptions table and the `Riskiest assumption:` line. Read `IDEA.md` for the people the user can reach. If `VALIDATION.md` exists, continue from it (see step 5).
2. **Plan the tests.** For each risky assumption, pick the cheapest test:
   - search and competitor check (do people already pay for this?)
   - talking to 3 to 5 people from the target group
   - a landing page with a sign-up
   - a mockup shown to people

   For each, write what result means **go** and what result means **stop**, as a number or a yes/no.
3. **Write the test plan** into `VALIDATION.md` (template below). Do the tests that need no one else now (search, competitors) and record them.
4. **Wait.** If tests need the user to talk to people, tell them what to do and stop. The orchestrator marks the stage `waiting`. Say clearly what evidence is needed.
5. **When the user returns,** record the evidence per assumption: what happened, with numbers, quotes, and links. Compare it to the go/stop rule written earlier.
6. **Decide.** End with `Decision: Go`, `Decision: Change`, or `Decision: Stop` and the reason. Ask for the user's yes. Add `Confirmed: <date>` after they agree.
   - **Go:** the riskiest assumption held.
   - **Change:** the problem is real but the brief is wrong somewhere. Say what to change.
   - **Stop:** the riskiest assumption failed, or evidence is too weak to justify building.

## Template

```markdown
# <Product name> - Validation

Date: YYYY-MM-DD | Confirmed: _(date, once you agree)_

## Test plan
| # | Assumption | Test | Go if | Stop if |
|---|------------|------|-------|---------|

## Evidence
| # | Result | Verdict | Source |
|---|--------|---------|--------|
<Verdict: held / failed / untested>

## Weak spots
<What the evidence does not prove.>

Decision: Go | Change | Stop
Reason: <1-3 sentences>
```

## Hand-off
If `STATUS.md` exists, end with "Run `/clear`, then `zero-to-prod` for the next stage." (The orchestrator handles Change and Stop.) Otherwise, on Go, end with: "Next, use the z2p-requirements skill, or project-planner."
