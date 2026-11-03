---
name: z2p-operate
description: Use as z2p stage 10, after the release, to watch the live product and plan what comes next (e.g. "set up monitoring", "alert me when it is down", "what should I fix next?", "start a backlog"). Sets up an uptime check and an alert that reaches the user, and writes BACKLOG.md.
---

# Z2P Operate (stage 10)

Makes production problems visible and turns them into the next round of work. Read `~/.claude/skills/z2p/CONVENTIONS.md` first.

## Rules
- Use free or already-chosen tools first (`N7` in a project's `REQUIREMENTS.md` may set a cost limit).
- Never print or commit secrets such as webhook URLs or API keys. Keep them in the host's secret store.
- Plain English. Short sentences.

## Steps

1. **Read.** `RELEASE.md` (where it is live, error tracking), `REQUIREMENTS.md` (the availability `N` requirement), and `BACKLOG.md` if it exists. If `RELEASE.md` has no `Release: approved` line, stop and say that stage 9 comes first.
2. **Uptime check.** Add a check on the live URL, or for a product with no URL, on the thing users get (a registry page, a download link). It runs often enough for the availability requirement.
3. **Alert.** Send alerts to a place the user reads, like e-mail or a chat message. Send one test alert and ask the user to confirm it arrived. Write where alerts go (not the secret) in `BACKLOG.md`.
4. **Error tracking.** Check that the tracker from the walking skeleton still works. Cause one test error and see it arrive.
5. **Look deeper where it fits.** Use `observability` for metrics, logs, and traces. Use `incident-triage` when something is already broken.
6. **Write `BACKLOG.md`.** Each item has a source (error, user feedback, idea), a rough size (S, M, L), and a value (low, medium, high). Start it with open errors and the Later items from `PLAN.md` and `REQUIREMENTS.md`.
7. **Pick.** Ask the user which items to do next. Say where each goes:
   - Adds a requirement: stage 4.
   - Changes the plan: stage 5.
   - Anything else: stage 7.
   The orchestrator counts the cycle. Do not edit `STATUS.md`.
8. **Gate check.** Errors and uptime are visible, an alert reached the user, and the backlog is started. Fix what fails.

## Template

````markdown
# <Product name> - Backlog

## Monitoring
- **Uptime check:** <tool, what it checks, how often>
- **Alerts go to:** <where>
- **Test alert confirmed:** YYYY-MM-DD
- **Error tracking:** <tool and where to look>

## Items
| # | Item | Source | Size | Value | Goes to |
|---|------|--------|------|-------|---------|
| 1 | | error / feedback / idea | S/M/L | low/medium/high | stage 4 / 5 / 7 |
````

## Hand-off
If `STATUS.md` exists, end with "Run `/clear`, then `z2p` for the next stage." Otherwise end with: "Pick backlog items, then use the plan-to-tasks skill."
