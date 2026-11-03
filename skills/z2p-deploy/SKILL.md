---
name: z2p-deploy
description: Use as the helper for the deploy tasks of a z2p project, like the walking skeleton and the release deploy (e.g. "deploy the skeleton", "set up hosting and CI", "put hello world live", "how do I roll back?"). Sets up host, secrets, CI, production database, error tracking, and one tried rollback, and writes the steps into RELEASE.md.
---

# Z2P Deploy (helper)

Puts the product live the same safe way every time. It runs inside the Stage 1 tasks of `TASKS.md` (the walking skeleton, D8) and again at release. It is not a numbered stage and writes no gate file of its own. Read `~/.claude/skills/z2p/CONVENTIONS.md` first.

## Rules
- Use the host chosen in `PLAN.md`. If it does not fit, stop and ask to change `PLAN.md` first.
- The simplest deploy that works. No extra services, no Kubernetes unless `PLAN.md` says so.
- Never put secrets in git. Never print them.
- Show each command that changes production before running it.
- Plain English. Short sentences.

## Steps

1. **Read.** The hosting in `PLAN.md`, the architecture, database, and cross-cutting sections of `DESIGN.md`, and the non-functional requirements (`N`) about availability, cost, and backup. If `RELEASE.md` exists, update it.
2. **Host.** Deploy the smallest working version (a hello-world page, endpoint, or command) to the chosen host.
   - No URL (CLI, library, app): deploy to where users get it, such as a package registry, an app store, or a download. Then install it from there and run it.
   - A container only if the host needs one. Then use `container-builds`, and run `docker-review` on the Dockerfile.
3. **Secrets.** Keep them in the host's secret store or CI secrets. Commit a `.env.example` with names only. Check that `.env` is in `.gitignore` and that no secret is in the git history.
4. **CI.** Use `ci-pipelines`. The pipeline runs the tests and then deploys from `main`. A failing test stops the deploy.
5. **Database.** Skip if `DESIGN.md` says "no stored data". Otherwise create the database in production, keep its credentials as secrets, and run migrations from the pipeline before the new version starts. Never run them by hand.
6. **Error tracking.** Add one error tracker. Cause a test error in production and check that it shows up.
7. **Rollback.** Try one: deploy a second version, roll back to the first, and check that the first is live again. If there is a database, say how a migration is undone or why it need not be.
8. **Infra review.** Run the reviewer that matches the files present: `terraform-reviewer`, `ansible-reviewer`, `packer-reviewer`, `network-reviewer`, `docker-reviewer`. Fix high findings now.
9. **Write `RELEASE.md`.** Fill the `## Deploy` and `## Rollback` sections from the template below. Keep every other section as is.
10. **Check.** The live version works where users get it, CI is green, the test error arrived, and the rollback was tried. Fix what fails.

## Coach mode
If the user says "coach me" or "teach me", or the orchestrator says so, use project-planner's coach mode for each decision here: host settings, secrets store, CI trigger, rollback method.

## Template

````markdown
# <Product name> - Release

## Deploy
- **Where it runs:**
- **Live at:** <URL, registry page, or download>
- **How to deploy:** <pipeline name and trigger, or exact commands>
- **Secrets:** <names and where they are stored>
- **Database and migrations:** <how they run, or "no stored data">
- **Error tracking:** <tool and where to look>

## Rollback
- **Steps:**
- **Tried on:** YYYY-MM-DD
- **Result:**
````

## Hand-off
Return to the task that called you. If `STATUS.md` exists and no task is running, end with "Run `/clear`, then `z2p` for the next stage."
