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

### [ ] T1.7: Test the setup on a clean home and a second PC, then commit
**What:** Prove that clone → "set up for Claude Code" works from nothing.
**Why:** This is the goal of the repo. It must not depend on anything only this PC has.
**How:**
- Clean home: `HOME=$(mktemp -d) ./install.sh`. Everything is linked. Run it again and nothing changes. Put a real folder at one target: it is reported and left alone, and `--backup` moves it. Remove a skill from a copy of the repo: its link is removed.
- On a second PC, or a new user account on this one: clone, open `claude`, say "set up for Claude Code", restart, and check the skills, agents, and plugins.
- Check R1 to R7 and N1 to N4 in `REQUIREMENTS.md`. Note any that fail in this task's Notes.
- Commit with the `git-commit` skill and push.
**Notes:** Clean-home part passed: 26 linked, re-run 26 already OK, a real folder was reported and left alone (exit 1), `--backup` moved it, a skill deleted from a repo copy had its link removed. Install took 0.13 s (N4), uses only bash and standard tools (N3, Linux only so far), and no `/home/` paths or secrets are in the repo (N1). Not done yet: the full flow (clone, say "set up for Claude Code", restart, settings merge R6, plugins R1) on a second PC or new user, a macOS run, and the push.

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
