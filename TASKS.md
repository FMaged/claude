# Claude Code Setup and z2p Skill Chain: Tasks

## Stage 1: Portable repo (clone, then "set up for Claude Code" works)

### [x] T1.1: Move all skills into `skills/` and bring the repo up to date
**What:** Every skill this PC uses ends up in `skills/<name>/`, using the newest copy of each.
**Why:** The repo is the only source (D6). Today it is missing 3 skills, and `git-commit` is out of date.
**How:**
- `git mv` the 15 skill folders from the repo root into `skills/`.
- Copy `svelte`, `svelte-review`, and `web-security-review` from `~/.claude/skills/` into `skills/`.
- Copy the installed `~/.claude/skills/git-commit/SKILL.md` over the repo copy. It is newer because it has the 72-character rule. Read the diff first.
- Keep the repo's `product-brief`. It already names `project-planner` correctly.
- Delete `product-brief.skill` (a zip of the same file) and add `*.skill` to `.gitignore`.
- This breaks nothing yet. `~/.claude/skills` still holds copies until T1.6.
**Notes:** _(added after implementation if anything came up)_

### [x] T1.2: Add the agents with paths that work on any PC
**What:** The 8 reviewer agents live in `agents/` and find their skill on any PC.
**Why:** Each agent reads `/home/deb/.claude/skills/<name>/SKILL.md`, which breaks for any other username.
**How:**
- Copy the 8 files from `~/.claude/agents/` into `agents/`.
- Check whether agent frontmatter can preload a skill (a `skills:` field). If it can, use that. If not, write the path as `~/.claude/skills/<name>/SKILL.md` and tell the agent to expand `~` to the home folder.
- Test one agent (`sql-reviewer` on a small SQL file) and check that it read the skill.
**Notes:** Frontmatter supports `skills:`, so each agent now preloads its skill (`skills: [<name>]`) and the body says "follow the preloaded <name> skill". No paths, so no `~` expansion needed. Tested `sql-reviewer` as a project agent: it quoted the skill's heading (`# SQL Review`) and used its severity labels. `claude --agents` JSON did not preload skills, so that is not a valid test.

### [x] T1.3: Add the shared settings
**What:** `settings/settings.json` with only the keys every PC should share.
**Why:** The impeccable and rust-analyzer plugins, the model, and the theme should follow you to a new PC. Secrets should not (D13).
**How:**
- Include `enabledPlugins`, `extraKnownMarketplaces` (impeccable from `pbakaus/impeccable`), `model`, and `theme`.
- No credentials and no MCP servers.
- The rust-analyzer plugin needs the `rust-analyzer` binary. The setup only warns if it is missing.
**Notes:** _(added after implementation if anything came up)_

### [x] T1.4: Write `install.sh`
**What:** A script that links `skills/*` and `agents/*.md` into `~/.claude`, the same way every time.
**Why:** The links must come out the same on every PC. Judgement calls are left to the setup skill (D11).
**How:**
- Create `~/.claude/skills/` and `~/.claude/agents/` if they are missing.
- For each skill folder and agent file:
  - Target missing → create a symlink (absolute path into the repo).
  - Already a link into this repo → leave it.
  - Anything else → report a conflict and do not touch it. With `--backup`, move it to `~/.claude/backups/install-<date>/` and then link.
- Remove links in `~/.claude` that point into this repo when their target is gone (a skill deleted from the repo).
- `--dry-run` prints the actions only. Always print a summary: linked, already OK, conflicts, removed. Exit 1 if conflicts remain.
- Use only bash and tools that also exist on macOS (no GNU-only flags).
- It does not touch settings. The setup skill does that.
**Notes:** _(added after implementation if anything came up)_

### [x] T1.5: Write the `setup-claude-code` skill, `CLAUDE.md`, and `README.md`
**What:** Saying "set up for Claude Code" in this repo runs the whole setup.
**Why:** This is the clone-and-ask flow the repo exists for (D11).
**How:**
- Create `.claude/skills/setup-claude-code/SKILL.md`. Trigger on "set up for Claude Code", "install my setup", "set up this PC". Steps:
  1. Check `git` and `bash`. Warn if `rust-analyzer` is missing.
  2. Run `./install.sh --dry-run` and show the summary.
  3. For each conflict, show the difference between the existing file and the repo file. Ask whether to back it up and link, or skip it.
  4. Run `./install.sh`, with `--backup` if chosen.
  5. Back up `~/.claude/settings.json`, then merge `settings/settings.json` into it. Add missing keys. Ask before changing a key that has a different value. Never drop the user's other keys.
  6. Ask the user to restart Claude Code so the plugins install and the skills load. After the restart, check that the skills and agents appear. If a plugin did not install, look up the current plugin install command and run it.
  7. List the manual steps: log in to claude.ai for synced skills, remove the claude.ai copy of `product-brief`, and add MCP servers by hand if wanted.
- `CLAUDE.md`, kept short:
  - What the repo is, and that "set up" means the setup skill.
  - `skills/` and `agents/` are linked live, so editing them changes Claude on this PC right away.
  - New skills go in `skills/<name>/SKILL.md`, followed by `./install.sh`.
  - Commit with the `git-commit` skill. Never put secrets here.
- `README.md`: what is in the repo, the 3-line setup (the SSH clone URL needs a GitHub key on that PC; HTTPS works if the repo is public), how to update (`git pull`, and re-run the setup when a skill is added or the repo folder moves), the manual steps, and platforms (Linux and macOS; Windows via WSL).
**Notes:** _(added after implementation if anything came up)_

### [x] T1.6: Switch this PC to the links
**What:** Replace the copies in `~/.claude/skills` and `~/.claude/agents` with links into the repo.
**Why:** After this, editing a skill edits the repo, and the copies can no longer drift.
**How:**
- Run the setup here. The dry run will show every existing skill and agent as a conflict.
- Check that each conflict matches its repo file (after T1.1 they should). Then choose "back up and link".
- Start a new session. Check that the skills and agents still load, and run one agent.
- Ask the user to remove `product-brief` from their claude.ai skills. After the next sync, check that only one `product-brief` appears.
**Notes:** Skills were identical to the repo; the 8 agents differed only by the T1.2 edit. Backed up all 25 to `~/.claude/backups/install-20261028-211631/` and linked. A fresh session loaded everything and `sql-reviewer` ran with its skill. Still open: `product-brief` appears twice (`product-brief` and `anthropic-skills:product-brief`) until the user removes it from claude.ai skills.

### [x] T1.7: Test the setup on a clean home and a second PC, then commit
**What:** Prove that clone → "set up for Claude Code" works from nothing.
**Why:** This is the goal of the repo. It must not depend on anything only this PC has.
**How:**
- Clean home: `HOME=$(mktemp -d) ./install.sh`. Everything is linked. Run it again and nothing changes. Put a real folder at one target: it is reported and left alone, and `--backup` moves it. Remove a skill from a copy of the repo: its link is removed.
- On a second PC, or a new user account on this one: clone, open `claude`, say "set up for Claude Code", restart, and check the skills, agents, and plugins.
- Check R1 to R7 and N1 to N4 in `REQUIREMENTS.md`. Note any that fail in this task's Notes.
- Commit with the `git-commit` skill and push.
**Notes:** Clean-home part passed: 26 linked, re-run 26 already OK, a real folder was reported and left alone (exit 1), `--backup` moved it, a skill deleted from a repo copy had its link removed. Install took 0.13 s (N4), uses only bash and standard tools (N3, Linux only so far), and no `/home/` paths or secrets are in the repo (N1). Not done yet: the full flow (clone, say "set up for Claude Code", restart, settings merge R6, plugins R1) on a second PC or new user, a macOS run, and the push. 2026-11-15: the clean-home part is now `evals/test-install.sh`, run by CI on Linux and macOS (N2, N3). The second-PC flow moved to T1.8.

### [ ] T1.8: Run the full setup flow on a second PC
**What:** Clone, say "set up for Claude Code", restart, and check skills, agents, plugins, and the settings merge.
**Why:** It is the only part of R1 and R6 that no script covers.
**How:**
- On a second PC, or a new user account on this one: clone, open `claude`, say "set up for Claude Code", restart.
- Check that every skill and agent appears, the plugins installed, and `~/.claude/settings.json` kept its own keys (R6).
- Note anything that failed in this task's Notes.
**Notes:** _(added after implementation if anything came up)_

## Stage 2: Chain foundation (orchestrator plus the 4 existing skills, end to end)

### [x] T2.1: Write `CONVENTIONS.md`
**What:** One file with the rules every chain skill follows.
**Why:** Every stage must read and write the same things, or the orchestrator cannot chain them. Skills running in other projects can read `~/.claude/skills/z2p/CONVENTIONS.md`. They cannot read this repo's `PLAN.md`.
**How:**
- Create `skills/z2p/CONVENTIONS.md`.
- Include:
  - The stage table from `PLAN.md`: stage, skill, file written.
  - The `STATUS.md` format: stage, state, gate result, date, note. States are `todo`, `doing`, `waiting`, `done`, `skipped`, `stale`. It also has a cycle counter.
  - The gate table, written as checks on files. Example: "`VALIDATION.md` has a line `Decision: Go`". Mark gates 3, 4, 5, 6, and 9 as needing a yes from the user.
  - The going-back rules and adopt mode.
  - The rules for stage skills: read the previous file, write one file, never touch `STATUS.md`, use the hand-off line.
**Notes:** Added a Going back section and a rule 6 for the `Confirmed:` line. Gate 9 checks a `Release: approved` line, so `z2p-release` must write it.

### [x] T2.2: Write the `z2p` orchestrator
**What:** The one entry point. It finds the next stage, runs it, checks the gate, and records the result.
**Why:** No lost place between sessions (D5).
**How:**
- Create `skills/z2p/SKILL.md` and run `./install.sh`. Trigger on "zero to prod", "next stage", "where is my project".
- Empty folder: run `git init`, then write `STATUS.md` (all stages `todo`) and a minimal `CLAUDE.md` that points to `STATUS.md` and the stage files.
- No `STATUS.md` but files or code exist: adopt the project. Check each gate, mark the passing stages `done`, and ask the user to confirm.
- Next stage:
  - Pick the first stage that is not `done` or `skipped`.
  - For stage 1, ask "Do you already have an idea?" and skip it if yes.
  - For a `waiting` stage, ask whether the evidence has arrived.
  - Run the stage's skill. At stage 5, ask "fast or coach mode?".
- After the stage:
  - Check the gate from the files. Ask for the user's yes at gates 3, 4, 5, 6, and 9.
  - Write `STATUS.md`. The orchestrator is the only thing that writes it.
  - End with "run `/clear`, then z2p again".
- Handle going back and `stale` stages as `CONVENTIONS.md` describes.
- After stage 5, add a "Skills for this project" line to `CLAUDE.md`, based on the chosen stack (for example `svelte`, `sql-writing`).
- If a stage skill is not installed yet, say so and offer to skip the stage. The thin dry run in T2.8 needs this.
**Notes:** _(added after implementation if anything came up)_

### [x] T2.3: Wire `product-brief` into the chain
**What:** It reads `IDEA.md` and hands back to the orchestrator.
**Why:** It was built standalone. Its hand-off jumps to planning and skips validation.
**How:**
- Read `IDEA.md` if present, and do not re-ask what it answers.
- Hand-off: if `STATUS.md` exists, end with "run z2p for the next stage". In the chain, its Go/Change/Stop verdict is a first opinion; `z2p-validate` makes the call.
- Keep the standalone hand-off for use outside the chain. Change nothing else.
**Notes:** _(added after implementation if anything came up)_

### [x] T2.4: Wire `project-planner` into the chain
**What:** It reads the earlier files, picks the database engine and hosting, and leaves the detailed model to the design.
**Why:** Stage 5 must build on the requirements, and must not duplicate `DESIGN.md` (D15, D16).
**How:**
- Read `IDEA.md`, `PRODUCT_BRIEF.md`, `VALIDATION.md`, and `REQUIREMENTS.md` if present. Do not re-ask what they answer.
- When `REQUIREMENTS.md` exists, list the MVP features by requirement ID instead of asking for them again. Use its non-functional requirements to choose the stack.
- Always ask about hosting and the database engine (or "no database").
- In the chain, keep Structure to one line per main entity and page. The detail goes in `DESIGN.md`.
- After the user confirms, add `Confirmed: <date>` under the title. The gate checks for it.
- Use the hand-off rule from `CONVENTIONS.md`.
**Notes:** _(added after implementation if anything came up)_

### [x] T2.5: Add coach mode to `project-planner`
**What:** A teaching mode where every recommendation is explained and can be argued with.
**Why:** The user wants to learn why each choice is best (D9).
**How:**
- Add a "Coach mode" section, turned on by "coach me" or "teach me", or picked at stage 5.
- Each question:
  - The question text says why the recommended option is best, and when it would be the wrong choice.
  - Each option's description says what that option costs.
- When the user argues back, answer the objection honestly. If their argument is right, change the recommendation. Then continue.
- Record the final reasoning in each decision's Why and Alternatives.
- Write the rules so `z2p-design` and `z2p-deploy` can say "use project-planner's coach mode".
**Notes:** _(added after implementation if anything came up)_

### [x] T2.6: Wire `plan-to-tasks` into the chain
**What:** It reads `DESIGN.md`, always starts with the walking skeleton, and builds tasks from the design.
**Why:** Deploy early (D8), and code should follow the design (D15).
**How:**
- Read `DESIGN.md` if present.
- When `PLAN.md` names a host, Stage 1 is always the walking skeleton:
  - Hello world, a test runner, CI, and a deploy to production.
  - Error tracking.
  - If there is a database: create it in production and run the first migration.
  - Try a rollback once.
  - These tasks say "use z2p-deploy".
- After the skeleton, make tasks from the `DESIGN.md` tables, interfaces, and flows. Each task's How names the section it builds and the requirement IDs it delivers.
- Check that every Must requirement is delivered by at least one task.
- Use the hand-off rule.
**Notes:** _(added after implementation if anything came up)_

### [x] T2.7: Wire `task-runner` into the chain
**What:** Tests with every task, reviews at the end of each task stage, and design changes recorded.
**Why:** Findings are cheapest right after the code is written (D10).
**How:**
- Follow `DESIGN.md` as well as `PLAN.md`.
- Write or update tests with each task when the project has a test setup. Turn the acceptance criteria of the requirements a task delivers into tests.
- When the last task of a `TASKS.md` stage is done, run the review skills that match the files changed in that stage (`sql-review` for SQL, `svelte-review` for Svelte, `docker-review` for Dockerfiles, and so on). Fix high findings now, or add them as tasks.
- If part of `DESIGN.md` must change, ask first. Then update it with a "Changed:" line, as already done for `PLAN.md`.
- Use the hand-off rule. Do not write `STATUS.md`.
**Notes:** _(added after implementation if anything came up)_

### [ ] T2.8: Dry-run the thin chain, then commit
**What:** Run the orchestrator and the 4 wired skills on a toy project.
**Why:** Find broken handoffs now, before 7 more skills depend on them.
**How:**
- In a temp folder, run `z2p` with a trivial idea (for example, "a page that lists my books").
- Skip stages 1, 3, 4, and 6, which are not built yet. Run brief → plan → tasks → the first task.
- Check each of these:
  - Each skill read the previous file.
  - Each gate was checked correctly.
  - `STATUS.md` is right.
  - `/clear` between stages lost nothing.
- Fix what broke and commit.
**Notes:** _(added after implementation if anything came up)_

## Stage 3: Pre-code stages (idea, validate, requirements, design)

### [x] T3.1: Write `z2p-idea` (stage 1)
**What:** Helps find a problem worth solving and writes `IDEA.md`.
**Why:** The process can start from zero.
**How:**
- Create `skills/z2p-idea/SKILL.md` and run `./install.sh`. The description says it is z2p stage 1 (D12).
- Interview about frustrations, skills, interests, and people the user can reach. Those people are needed for validation.
- List 3 to 5 candidate problems. Narrow to one problem and one target user. Write `IDEA.md`.
- Check: run the toy project through stage 1, and confirm `product-brief` reads `IDEA.md`.
**Notes:** _(added after implementation if anything came up)_

### [x] T3.2: Write `z2p-validate` (stage 3)
**What:** Tests the brief's risky assumptions and writes `VALIDATION.md` with the go/no-go.
**Why:** Stops a bad idea before any planning or code. This stage owns the decision.
**How:**
- Create `skills/z2p-validate/SKILL.md` and run `./install.sh`.
- Read the brief's Risks and assumptions table and the riskiest assumption.
- For each risky assumption, write:
  - The cheapest test: search, competitors, talking to 3 to 5 people, a landing page, or a mockup.
  - Which result means go and which means stop, decided before running the test.
- Write the test plan into `VALIDATION.md`. The stage then waits while the user runs the tests.
- When the user comes back, record the evidence. Mark any assumption not tested as untested. Say so plainly if the evidence is weak.
- End with `Decision: Go / Change / Stop` and the reason. Ask for the user's yes.
- Check: run the toy project through it, and confirm `z2p-requirements` reads `VALIDATION.md`.
**Notes:** _(added after implementation if anything came up)_

### [x] T3.3: Write `z2p-requirements` (stage 4)
**What:** Turns the brief and validation into `REQUIREMENTS.md`: users and roles, functional requirements with acceptance criteria, non-functional requirements, constraints.
**Why:** No stage wrote requirements, so there was nothing concrete to design, test, or release against (D16).
**How:**
- Create `skills/z2p-requirements/SKILL.md` and run `./install.sh`.
- Read `PRODUCT_BRIEF.md` (users, MVP scope, success signs) and `VALIDATION.md` (what was learned).
- Use the format of this repo's `REQUIREMENTS.md`:
  - Each functional requirement has an ID (`R1`, …), a priority (Must or Later), a user story, and acceptance criteria that are yes/no checks.
  - Each non-functional requirement has an ID (`N1`, …) and says how it will be checked.
- Go through every non-functional topic (performance, availability, security, privacy and personal data, accessibility, platforms, data retention and backup, scale, cost, compliance). Answer each one or mark it "not needed". If personal data is stored, privacy law (GDPR in the EU) is never "not needed".
- Push back on criteria that cannot be tested, like "fast" or "easy". Ask for a number or a yes/no check instead.
- Every MVP item in the brief must have at least one Must requirement. Anything else goes to Later.
- Run the stage 4 gate checks and ask the user to confirm. Add `Confirmed: <date>` to the status line.
- Check: run the toy project through it, and confirm `project-planner` lists the MVP by requirement ID.
**Notes:** _(added after implementation if anything came up)_

### [x] T3.4: Write `z2p-design` (stage 6)
**What:** Turns `PLAN.md` into `DESIGN.md`: user flows, architecture, entities, database, interfaces, permissions, cross-cutting rules, folder layout, and design decisions.
**Why:** Code, tasks, and reviews need one design to follow. The data model is the most expensive thing to change later (D15).
**How:**
- Create `skills/z2p-design/SKILL.md` and run `./install.sh`.
- Read `PLAN.md` and `REQUIREMENTS.md`.
- Write the 9 sections from "REQUIREMENTS.md, PLAN.md, and DESIGN.md" in that order. Flows come first, because everything else serves them. Each flow names the requirement IDs it covers, and every Must requirement is in at least one flow.
- Architecture: one Mermaid diagram with every part and where it runs, matching the hosting in `PLAN.md`.
- Database: run `schema-design` for the tables, writing into `## Database`. Write "no stored data" if there is none.
- Permissions: a table of role × data × action.
- UI: if there is a frontend, offer `impeccable` for the look and link its output.
- For design decisions, follow `project-planner`'s coach mode rules when coach mode is on.
- Run the stage 6 gate checks and ask the user to confirm.
- Check: use a toy idea with 2 tables, and confirm `plan-to-tasks` makes tasks from the tables and interfaces.
**Notes:** _(added after implementation if anything came up)_

### [x] T3.5: Wire `schema-design` into the chain, then commit
**What:** It writes into `DESIGN.md` and stops pointing at a skill that does not exist.
**Why:** In the chain, the schema lives in `DESIGN.md`. The "migration review skill" it names does not exist yet.
**How:**
- Add the `DESIGN.md` `## Database` section as the first place to write, when that file exists.
- Point the migration review mention to `sql-review` until a migration skill exists.
- Change nothing else. Commit Stage 3.
**Notes:** _(added after implementation if anything came up)_

## Stage 4: Ship stages (deploy helper, release, operate)

### [x] T4.1: Write `z2p-deploy` (helper for the walking skeleton and release)
**What:** Guides the deploy tasks: host setup, secrets, CI, database in production, error tracking, rollback.
**Why:** Stage 1 of every `TASKS.md` deploys on day one (D8). This skill makes sure it is done the same safe way each time.
**How:**
- Create `skills/z2p-deploy/SKILL.md` and run `./install.sh`.
- Read the hosting choice in `PLAN.md`, and the architecture and database in `DESIGN.md`.
- Cover:
  - The simplest deploy to the chosen host.
  - Secrets kept out of git.
  - CI that tests and deploys (`ci-pipelines`).
  - A container only if the host needs one (`container-builds`, `docker-review`).
  - The database created in production, with migrations run by the pipeline.
  - Error tracking.
  - One rollback tried. Write the deploy and rollback steps into `RELEASE.md`.
- For a product with no URL, deploy to where users get it (a package registry, an app store, a download) and test installing it from there.
- Run the infra reviewers (terraform, ansible, packer, network, docker) when those files exist.
- Support coach mode for its decisions.
- Check: deploy the toy project's hello world to a free host.
**Notes:** _(added after implementation if anything came up)_

### [x] T4.2: Write `z2p-release` (stage 9)
**What:** A final full review, then the MVP release over the existing pipeline.
**Why:** The release gate needs proof, not hope. Tests, reviews, backups, and rollback are checked once more before real users arrive.
**How:**
- Create `skills/z2p-release/SKILL.md` and run `./install.sh`.
- Run the tests, and check that CI is green.
- Check every Must requirement's acceptance criteria. Record a pass or fail for each one in a table in `RELEASE.md`. A fail blocks the release, unless the user moves that requirement to Later.
- Detect the file types and run each matching review skill. Always run `web-security-review` against the `DESIGN.md` permissions, and `sql-review` against the database section.
- List findings by severity in `RELEASE.md`. Each high finding is either fixed, or accepted by the user with a reason.
- If there is data, set up backups and try one restore.
- Deploy the MVP. Check that it works where users get it, and that the rollback steps are current.
- Write release notes in `RELEASE.md` and ask for the user's yes.
**Notes:** _(added after implementation if anything came up)_

### [x] T4.3: Write `z2p-operate` (stage 10), then commit
**What:** Uptime checks, alerts that reach the user, and a backlog that loops back into the chain.
**Why:** Production problems must be seen and turned into fixes.
**How:**
- Create `skills/z2p-operate/SKILL.md` and run `./install.sh`.
- Set up an uptime check and an alert, and send one test alert to confirm it reaches the user. Check that the error tracking from the skeleton still works.
- Use `observability` and `incident-triage` where they fit.
- Write `BACKLOG.md`: errors, user feedback, and ideas, each with a rough size and value.
- When the user picks items, the orchestrator sends them to stage 7. An item that adds a requirement goes to stage 4 instead, and one that changes the plan goes to stage 5. The cycle counter goes up by 1.
- Commit Stage 4.
**Notes:** _(added after implementation if anything came up)_

## Stage 5: Prove it works

### [x] T5.1: Check that the new skills trigger correctly
**What:** Each new skill fires when it should, and not when it shouldn't.
**Why:** A misfiring stage skill writes files the user did not ask for (D12).
**How:**
- For `z2p`, each `z2p-*` skill, and `setup-claude-code`, write 2 prompts that should trigger it and 2 that should not. Examples: "design a logo" must not trigger `z2p-design`, and "deploy this k8s manifest" must not trigger `z2p-deploy`.
- Fix descriptions that miss or misfire. `skill-creator` can run these as evals.
**Notes:** Ran as a script instead of `skill-creator`: `evals/run-trigger-evals.sh [skill]` runs `claude -p` (haiku, 1 turn) on the 36 prompts in `evals/trigger-prompts.tsv` and checks which skill fires. `setup-claude-code` lives in `.claude/skills/` of this repo (project-level), so its prompts run from the repo. First run: 35 of 36 correct, no misfires. Only miss: "design the app, I have a PLAN.md ready" in an empty folder (the model lists files first). Added "PLAN.md is ready, what next?" and a "Not for logos, UI looks, or visual design" line to the `z2p-design` description. Re-runs: that prompt passed 2 of 3 times, so it stays a little flaky when no PLAN.md is in the folder. The "server is down" prompt fired `incident-triage`, not `z2p-operate`, which is correct.

### [ ] T5.2: Full dry run on a tiny real project
**What:** Run all stages, 0 to 10, on a project that really deploys.
**Why:** Only a full run proves the handoffs, the gates, and the database path all work together.
**How:**
- Pick an idea with 1 or 2 tables that can be hosted for free.
- Run one stage per session, with `/clear` in between.
- Record each gate result in this task's Notes.
- Check R8 to R16 and N5 to N7 in `REQUIREMENTS.md`.
**Notes:** _(added after implementation if anything came up)_

### [ ] T5.3: Fix, update the plan, re-test on the second PC, commit
**What:** Fix what the dry run found and leave a working, saved chain.
**Why:** The second PC must get the finished chain through the normal update path.
**How:**
- Fix the affected skills. Add a "Changed:" line to any `PLAN.md` decision that changed, and update `REQUIREMENTS.md` if a requirement changed.
- On the second PC: run `git pull`, re-run the setup, and check that the new skills appear.
- Commit with the `git-commit` skill.
**Notes:** _(added after implementation if anything came up)_

## Stage 6: Hardening (chain fix, checks, evals, docs)

### [x] T6.1: Put the validate stage into the z2p conventions
**What:** Add the stage 3 row to the stage table in `CONVENTIONS.md`, the Stop and Change rules under Going back, and the stage 3 yes to the orchestrator.
**Why:** The orchestrator runs each stage's skill from that table. Without the row, `z2p` went from Brief straight to Requirements.
**How:** Edit `skills/z2p/CONVENTIONS.md` and `skills/z2p/SKILL.md`. Replace the hardcoded `~/.claude/skills/z2p/CONVENTIONS.md` path in every stage skill with "`CONVENTIONS.md` in the `z2p` skill folder", so Codex finds it too.
**Notes:** Done 2026-11-15.

### [x] T6.2: Drop references to skills that do not exist
**What:** Replace `container-builds`, `ci-pipelines`, `frontend-code-review`, and "the migration skill" with what the repo has.
**Why:** Those names are anthropic-skills plugin skills that are turned off on this PC, so Claude found nothing when a skill named them.
**How:** `z2p-deploy` describes the Dockerfile and pipeline itself and runs `docker-review`; `schema-design` hands the migration to `task-runner` and `sql-review`; `web-security-review` names `svelte-review`.
**Notes:** Done 2026-11-15.

### [x] T6.3: Add a lint, an install test, and CI
**What:** `evals/lint.sh` (frontmatter, agent skills, cross-references, `/home/` paths, secrets, eval coverage, settings JSON, shellcheck), `evals/test-install.sh` (R2, R3, R4 on an empty home), and `.github/workflows/check.yml` running both on Linux and macOS.
**Why:** Until now only a human could find a broken reference or a regression in `install.sh`. The macOS runner also covers the macOS half of N2.
**How:** Plain bash, no dependencies beyond python3 for the JSON check. Lint fails if a skill has no trigger eval.
**Notes:** Done 2026-11-15. shellcheck was not installed on this PC at first, so only CI ran it.

### [x] T6.4: Add trigger evals for every remaining skill
**What:** Two prompts that should fire and two that should not, for each of the 18 skills that had none. The runner skips skills turned off in `~/.claude/settings.json`.
**Why:** N5 applied only to the z2p skills.
**How:** Append to `evals/trigger-prompts.tsv`; run `evals/run-trigger-evals.sh`.
**Notes:** Run on 2026-11-15 with haiku: 88 ok, 20 skipped (the five skills turned off in `skillOverrides`, see T6.6), 4 failed. All four failures were a positive prompt where no skill fired; no prompt fired the wrong skill. `validate my idea` passed on a rerun. Still missing on a rerun, all in an empty folder with no file to look at: `are the comments in this file any good?` (code-comments), `should members and staff be one table or two?` (schema-design), `add an upsert for the settings table` (sql-writing). Likely the harness, not the descriptions: haiku asks for the file instead of calling a skill. Check with a real file before changing those descriptions.

### [x] T6.5: Bring the docs up to date
**What:** `PLAN.md` structure and stack mention Codex and the checks (D6 has a Changed line). `REQUIREMENTS.md` closes two open questions and points N1 to N5 at the scripts. `README.md` lists the checks and the manual graphify install. Agents no longer mention a night run. `product-brief` gets trigger phrases like the other skills. The shared settings pin the model that is used today.
**Why:** The docs still described the Claude-only installer and left questions open that were long answered.
**Notes:** Done 2026-11-15.

### [x] T6.6: Decide what to do with the five review skills turned off on this PC
**What:** `~/.claude/settings.json` has `skillOverrides` that turn off `ansible-review`, `network-review`, `packer-review`, `terraform-review`, and `svelte-review`. The agents still preload them. The same file turns off the built-in `terraform-iac`, `powershell`, `ci-pipelines`, and `container-builds`, which D17 relies on. Decide whether that is wanted, and if so record it in the README or move the overrides into `settings/settings.json` so every PC matches.
**Why:** The repo cannot reproduce the setup if part of it lives only in the local settings file. The trigger evals for those five skills are skipped here, and a second PC would get the built-in Terraform skill competing with `terraform`.
**Notes:** Done 2026-11-15. Wanted: the five review skills run only through their reviewer agents, so the chain names the agents. All nine overrides moved into `settings/settings.json`; `setup-claude-code` merges `skillOverrides` like the other nested objects. The trigger evals of the five stay skipped on every PC; Codex still sees the skills, because `skillOverrides` is a Claude Code setting. The other built-in overrides on this PC stay local.

## Stage 7: VM skills (Terraform, Packer, PowerShell for Hyper-V)

### [x] T7.1: Write the `terraform` skill with a Hyper-V reference file
**What:** `skills/terraform/SKILL.md` for writing Terraform, plus `references/hyperv.md` for the `taliesins/hyperv` provider (D18, D23).
**Why:** Only the review half exists. The writing skill is what shapes a module before `terraform-review` sees it.
**How:**
- SKILL.md in the style of `svelte` and `sql-writing`: one root module per environment, modules per thing; `required_version` and pinned providers with the lock file committed; variables with `type`, `description`, and `validation`; `for_each` keyed by name, never `count` over a list; outputs that feed the Ansible inventory (`local_file`, as in `~/elab`); the GitLab HTTP state backend configured from `CI_` variables, plan on merge request, apply on `main`; a "Before calling it done" list.
- `references/hyperv.md`: provider setup over WinRM to the host with credentials from variables; a VM from the golden VHDX (differencing disk versus copy, and when each is right); generation 2, secure boot templates, checkpoints off, switches and VLANs, static MAC when DHCP reservations exist; injecting cloud-init or `unattend.xml` for first boot; what the provider cannot do and hands to PowerShell.
- Worked example in `evals/examples/terraform/` (D26): one VM module and a root module; run `terraform validate` (download the binary once, or `tofu`).
- Add 2 + 2 prompts to `evals/trigger-prompts.tsv`, run `evals/lint.sh` and the evals for the skill, commit.
**Notes:** Skill, reference, and evals done 2026-11-15; trigger evals 4 of 4. The reference was checked against the provider 1.2.1 docs and source, which changed four things from the plan: (1) the provider *can* set nested virtualization (`vm_processor.expose_virtualization_extensions`), so T7.3 should not list it as a PowerShell-only gap; (2) almost any in-place change to `hyperv_machine_instance` (even `notes`, adaptors, DVD drives) shuts the VM down with `Stop-VM -Force` and starts it again, so the skill says every in-place update is a reboot; (3) the `hyperv_vhd` data source does not fail on a missing file, and its `exists` is inverted in 1.2.1, so image lookups need a postcondition on `self.path != ""`; (4) `hyperv_iso_image` volume names are upper case only, so the cloud-init seed is `CIDATA`. Windows first boot uses `Autounattend.xml` on a seed ISO; Setup reads `%WINDIR%\Panther` first, so T7.2 must make sure the Packer image leaves no answer file there. Changed `terraform-review`: a committed `terraform.tfvars` with non-secret environment values is now fine (only secrets and personal values are flagged), because the skill keeps each environment's values in its root module's `terraform.tfvars`. The worked example (one `hyperv-vm` module, a `staging` root module) is written; `terraform validate` has not run yet, because downloading and running the Terraform binary was blocked on this PC. After the 2026-11-15 review the example moved to `evals/examples/terraform/` and follows the fixed reference; `evals/lint.sh` validates it once `terraform` is installed. Passed on 2026-11-15 with Terraform 1.17.2: `fmt -check` and `validate` are clean, the lock file `init` wrote is committed, and the trigger evals ran 4 of 4 again. Nothing was applied to a host; that is T7.5. With shellcheck installed, the lint also found six warnings in the eval scripts that CI would have failed on; they are fixed.

### [ ] T7.2: Write the `packer` skill
**What:** `skills/packer/SKILL.md` for building Hyper-V golden images (D18).
**Why:** The VMs clone an image; a bad image is cloned many times. `packer-review` exists, the writing side does not.
**How:**
- HCL2 only, `required_plugins` pinned, variables for secrets from `PKR_VAR_` environment variables, image names with date and git sha.
- Windows: `hyperv-iso` builder, `autounattend.xml` that enables WinRM for the build only, PowerShell provisioners, Windows Update step, sysprep with generalize as the last provisioner.
- Linux: autoinstall or preseed, cloud-init left enabled and cleaned for first boot, shell and `ansible` provisioners. Install the Hyper-V daemons (`hyperv-daemons` on Debian and RHEL, `linux-cloud-tools-virtual` on Ubuntu), or Terraform's `wait_for_ips` waits until it times out.
- Windows first boot reads `Autounattend.xml` from the seed ISO that Terraform attaches (`terraform/references/hyperv.md`). Setup reads `%WINDIR%\Panther` first, so the image must leave no answer file there, or the seed is ignored. Remove the build's answer file after sysprep, and say so in the skill.
- Build runs on the `hyperv` runner tag from GitLab CI; output goes to the image store Terraform reads (D21).
- Worked example in `evals/examples/packer/`: a Windows Server template; run `packer validate`. Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T7.3: Write the `powershell` skill
**What:** `skills/powershell/SKILL.md` for scripts and modules on Windows hosts and the Hyper-V host (D18).
**Why:** PowerShell fills the gaps Packer and Terraform leave, and it is the one tool here with no skill at all.
**How:**
- `#Requires -Version 7`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `try`/`catch` only where the script can do something about it.
- Functions with `[CmdletBinding(SupportsShouldProcess)]`, typed parameters with validation attributes, `-WhatIf` that really does nothing.
- Idempotent: `Get-` before `New-`, exit code 0 when nothing changed. Objects on the pipeline, `Write-Host` only for people. Credentials as `PSCredential` from CI variables or SecretManagement, never plain text.
- Remoting with `Invoke-Command`; the Hyper-V module for what the Terraform provider cannot do, as listed at the end of `terraform/references/hyperv.md`: the virtual TPM (`Set-VMKeyProtector`, `Enable-VMTPM`), trunk VLANs, `Copy-VMFile`, cluster roles and replication. Firmware, nested virtualisation, and integration services are in the provider, so a script must not set them: the next plan would revert it. Such a script runs as its own pipeline step after the apply.
- Modules with a manifest, Pester tests, PSScriptAnalyzer clean.
- Worked example in `evals/examples/powershell/`: a script that gives a VM a virtual TPM (key protector, then `Enable-VMTPM`), idempotent and honest under `-WhatIf`, checked with `Invoke-ScriptAnalyzer` under `pwsh` (install `pwsh` on this PC once). Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T7.4: Write `powershell-review` and the `powershell-reviewer` agent
**What:** `skills/powershell-review/SKILL.md` and `agents/powershell-reviewer.md` (D17).
**Why:** Scripts that touch the Hyper-V host and production VMs need an unattended check.
**How:**
- Review sections like `ansible-review`: what fails silently (no `Stop`, `-ErrorAction SilentlyContinue`, unchecked `$LASTEXITCODE`); what is not idempotent or lies under `-WhatIf`; what leaks secrets (plain-text passwords, `ConvertTo-SecureString -AsPlainText` from a literal, secrets in logs); what breaks under StrictMode or remoting; unpinned module versions; a Commands section (`Invoke-ScriptAnalyzer`, `Invoke-Pester`); "How to report".
- Agent copied from `agents/sql-reviewer.md` with the names changed.
- Evals for the review skill, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T7.5: Try the Hyper-V reference on a host
**What:** Apply the worked example in `evals/examples/terraform/` once against a Hyper-V host and record what the provider really does.
**Why:** Every Hyper-V statement in `references/hyperv.md` comes from reading the provider's source. Several fixes from the 2026-11-15 review (the image check, image replacement, differencing disks, the switch lookup, seed changes, the service account) change behaviour that was never run.
**How:**
- Use the service account you plan to keep. Write down the rights it really needed and correct the list in the reference.
- Plan with a missing image and with a wrong-case switch name: both plans must fail.
- Apply one Linux and one Windows VM. Plan again: no changes.
- Change one VM's image: the plan must show the disk, the seed ISO, and the VM as `must be replaced`, and the new VM must boot from the new image.
- Edit the cloud-config: the plan must show no change to running VMs.
- Destroy one VM and check that no other VM's files were deleted.
- Fix the reference and the example where the host disagrees. Commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T7.6: Teach `packer-review` about Windows images
**What:** Add the Windows image checks to `skills/packer-review/SKILL.md`.
**Why:** The review was written for Linux images. A Windows golden image fails in its own ways, and a bad image is cloned into every VM. T8.2 does the same for `ansible-review`.
**How:** Add: sysprep `/generalize /oobe` missing or not the last provisioner; an answer file left in `%WINDIR%\Panther` (the seed ISO's `Autounattend.xml` is then ignored); the build's WinRM listener, firewall rule, or build account left enabled; a Windows Update step without a `windows-restart` after it; the Administrator password from a literal instead of a `PKR_VAR_` variable; on Linux images, the Hyper-V daemons missing. Keep the existing sections. Commit.
**Notes:** _(added after implementation if anything came up)_

## Stage 8: Configuration (Ansible)

### [ ] T8.1: Write the `ansible` skill
**What:** `skills/ansible/SKILL.md` for playbooks and roles that configure Windows and Linux VMs (D19, D24).
**Why:** The hosts need IIS and Web Deploy, nginx and systemd, or Docker before any app can land. Only the review half exists.
**How:**
- Layout: inventory written by Terraform, `group_vars` per role and environment, one playbook per purpose, roles with defaults and handlers; FQCN module names.
- Idempotency: `changed_when`, `creates`, check mode works; `no_log` on tasks with secrets; secrets from environment variables set by CI, Ansible Vault only for files in the repo.
- Windows: `ansible_connection: winrm` with `kerberos`, `win_feature` for IIS and the Web Deploy install, `win_service`, `win_reboot` where a feature needs it, `become` with `runas`.
- Linux: nginx site, systemd unit for Kestrel, Docker engine; the same role shape as `~/elab/ansible`.
- Runs from the `docker` runner tag with `pywinrm` and Kerberos in the image.
- Worked example: a role that prepares an IIS host; `ansible-lint` and `ansible-playbook --syntax-check` (installed here). Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T8.2: Teach `ansible-review` about Windows hosts
**What:** Add the Windows checks to `skills/ansible-review/SKILL.md`.
**Why:** The review was written for Linux hosts. WinRM, `win_` modules, and reboots have their own ways to fail.
**How:** Add: `become` without `runas` on Windows; `win_reboot` missing after a feature install; NTLM or basic transport outside a lab; `win_shell` where a `win_` module exists; Kerberos ticket handling in CI. Keep the existing sections. Commit.
**Notes:** _(added after implementation if anything came up)_

## Stage 9: App pipeline (GitLab CI, .NET, Angular, Docker)

### [ ] T9.1: Write the `gitlab-ci` skill
**What:** `skills/gitlab-ci/SKILL.md` for the templates repo and for the app repos that include it (D21, D22, D23).
**Why:** The pipeline is where build-once, runner tags, and secrets handling are enforced. Nothing in the repo covers it.
**How:**
- Two audiences in one skill: writing a template in `ci-templates`, and the three-line `.gitlab-ci.yml` of an app that includes it pinned to a tag and sets its variables.
- Stages build, test, package, deploy-staging, deploy-prod; `rules:` and a `workflow:` block, never `only`/`except`; `needs:` for the graph; artifacts with `expire_in`; cache keyed by the lockfile; `image:` pinned to a version; runners by `tags:` only.
- `environment:` with `url` and `action`; the prod job `when: manual`, `resource_group`, protected refs; the deploy job downloads the build job's artifact or reuses the image digest, never rebuilds.
- Terraform jobs with the GitLab state backend, Packer build on `hyperv`, Ansible run on `docker`; masked variables, nothing secret in logs.
- Worked example: a template for a .NET app with the three deploy jobs, checked with `yamllint` and GitLab's CI lint if a token is at hand. Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T9.2: Write `gitlab-ci-review` and the `gitlab-ci-reviewer` agent
**What:** `skills/gitlab-ci-review/SKILL.md` and `agents/gitlab-ci-reviewer.md` (D17).
**Why:** A pipeline that rebuilds for prod, runs on any runner, or prints a secret is invisible until it hurts.
**How:** Sections: jobs without `tags` or with runner or host names; a prod job without `manual`, `resource_group`, or protected refs; a rebuild instead of a promote; `only`/`except`; unpinned includes and images; artifacts without expiry; `allow_failure` on tests; missing `workflow` rules (duplicate pipelines); secrets echoed or passed as unmasked variables. Agent from `sql-reviewer.md`. Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T9.3: Write the `dotnet` skill
**What:** `skills/dotnet/SKILL.md` for ASP.NET Core on .NET 10 with three publish targets (D19, D20).
**Why:** The C# apps are what the pipeline ships, and the skill must publish for IIS, Linux, and Docker from one build.
**How:**
- Solution layout `src/` and `tests/`, `Directory.Build.props`, central package management, nullable and warnings as errors, analyzers.
- Config by `appsettings.json` plus environment variables through the options pattern, no secrets in any appsettings; health endpoints; structured logging; EF Core migrations as a pipeline job with an idempotent script, never at startup.
- Tests with xUnit and `WebApplicationFactory`.
- Publish: Web Deploy package and the `msdeploy -verb:sync` call; framework-dependent folder with a systemd unit (own user, `Restart=always`, `DOTNET_` variables) behind nginx; multi-stage Dockerfile from the sdk and aspnet images, non-root. Version from the pipeline.
- Worked example: `dotnet new webapi` with a test project; `dotnet build` and `dotnet test` (installed here). Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T9.4: Write `dotnet-review` and the `dotnet-reviewer` agent
**What:** `skills/dotnet-review/SKILL.md` and `agents/dotnet-reviewer.md` (D17).
**Why:** The usual production failures in .NET apps are quiet: sync over async, migrations at startup, config baked in.
**How:** Sections: what leaks (secrets in appsettings, connection strings in code, exception details to clients); what blocks (`.Result`, `.Wait()`, missing cancellation tokens, `HttpClient` created per call); what breaks in prod (migrations at startup, environment-specific config in the artifact, no health check, warnings ignored); what is untested; packages unpinned or vulnerable (`dotnet list package --vulnerable`). Agent from `sql-reviewer.md`. Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T9.5: Write the `angular` skill
**What:** `skills/angular/SKILL.md` for current Angular with run-time configuration (D20).
**Why:** One production build has to serve staging and prod (D22), and the Angular apps deploy as static files on three hosts.
**How:**
- Standalone components, signals, the new control flow, `inject()`, strict TypeScript, `OnPush`; lazy routes.
- Configuration loaded at start from `config.json` next to the app, never from build-time environment files.
- HTTP interceptors for auth and errors; tests with the runner the CLI sets up; `angular-eslint`; `ng build --configuration production` with budgets.
- Deploy as static files: IIS with a `web.config` rewrite to `index.html`, nginx with `try_files`, or an nginx Docker image.
- Worked example: a new app with one lazy route and the config loader; `ng build` through `npx`. Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T9.6: Write `angular-review` and the `angular-reviewer` agent
**What:** `skills/angular-review/SKILL.md` and `agents/angular-reviewer.md` (D17).
**Why:** The build-once rule and a few security mistakes are easy to break in a frontend and hard to see in a diff.
**How:** Sections: what leaks (secrets in environment files, tokens stored without reason); what breaks build-once (build-time environment switches); what stops updating or leaks memory (subscriptions, mutated signal state); what is slow (no lazy routes, bundles over budget); XSS (`bypassSecurityTrust`, `innerHTML`); what is untested; basic accessibility. Agent from `sql-reviewer.md`. Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T9.7: Write the `docker` skill
**What:** `skills/docker/SKILL.md` for Dockerfiles and compose files of the apps that deploy as images (D19).
**Why:** `docker-review` exists; the writing side does not, and image tags are how promotion works for this path.
**How:** Multi-stage builds, pinned base images, non-root user, `HEALTHCHECK`, `.dockerignore`, labels with the git sha; images in the GitLab registry as `$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA`, promoted by re-tagging, never rebuilt; compose for one host with restart policies, env from files, named volumes, log limits; no secrets in build args; image scan in CI. Worked example: the Dockerfile from T9.3 built with `docker build` (installed here). Evals, lint, commit.
**Notes:** _(added after implementation if anything came up)_

### [ ] T9.8: Wire the new reviewers into the chain and the docs
**What:** The chain and the README know the four new reviewers and the eight writing skills.
**Why:** `task-runner` step 7, `z2p-deploy` step 8, and `z2p-release` pick reviews by file type; without this they skip PowerShell, pipelines, .NET, and Angular.
**How:** Add the mappings (`.ps1` to `powershell-review`, `.gitlab-ci.yml` to `gitlab-ci-review`, `.cs` and `.csproj` to `dotnet-review`, Angular files to `angular-review`) to `task-runner`, `z2p-deploy`, and `z2p-release`. Update the README agents line and the Structure in `PLAN.md`. Run `./install.sh`, `evals/lint.sh`, and the full trigger evals once, and check R17 in `REQUIREMENTS.md`. Commit.
**Notes:** _(added after implementation if anything came up)_
