# Claude Code Setup and z2p Skill Chain

## Goal
One git repo that holds my whole Claude Code setup. On any PC: clone it, open Claude in it, say "set up for Claude Code", and every skill, agent, and shared setting is installed.

The repo also holds the z2p skill chain: a repeatable process that takes a solo project from idea to production and beyond. One orchestrator skill walks through the stages. Each stage is a skill that also works alone.

The repo also holds the DevOps skill set (Part C): the skills and reviewer agents for the production toolchain at work. Packer builds Hyper-V images, Terraform creates the VMs, Ansible configures them, GitLab CI builds and deploys .NET and Angular apps to IIS, Linux, and Docker.

What the repo must do, and how to check it, is in `REQUIREMENTS.md`.

## MVP Features
**Part A: portable setup**
- Every skill and agent lives in this repo. Nothing is edited in `~/.claude` directly.
- `install.sh` links the repo's skills into `~/.claude/skills` and `~/.agents/skills` (Codex), and the agents into `~/.claude/agents`. It is safe to re-run, has a `--dry-run`, and never overwrites a real folder.
- A project skill, `setup-claude-code`, runs the whole setup when Claude is opened in this repo. It checks prerequisites, handles conflicts, runs `install.sh`, and merges the shared settings.
- The agents work on any PC. There are no hardcoded `/home/deb` paths.
- `README.md` explains how to set up, how to update, and what stays manual.

**Part B: z2p chain**
- `z2p` orchestrator plus `CONVENTIONS.md` (file names, `STATUS.md` format, gates).
- Stages 0 to 10 (see the table below), with a gate at the end of each one.
- The existing skills are wired into the chain. Eight new skills are added.
- Stage 4 writes `REQUIREMENTS.md`: user stories with acceptance criteria, plus non-functional needs. Every requirement has an ID that design, tasks, and release refer back to.
- Stage 6 designs the architecture, entities, database, interfaces, and permissions in `DESIGN.md`.
- Deploy happens early: the first stage of every `TASKS.md` puts a hello-world version live.

**Part C: DevOps skills** (decisions D17 to D26)
- A writing skill for each tool: `terraform` (with a Hyper-V reference file), `packer`, `powershell`, `ansible`, `gitlab-ci`, `dotnet`, `angular`, `docker`.
- A review skill and a read-only reviewer agent for the tools that have none yet: `powershell-review`, `gitlab-ci-review`, `dotnet-review`, `angular-review`, and their `*-reviewer` agents. The existing terraform, packer, ansible, and docker reviews are reused.
- The skills encode one way of working: Packer image, then Terraform VM, then Ansible; one central GitLab CI templates repo that app repos include; build once, promote the same artifact; secrets in GitLab variables; Terraform state in GitLab.
- `task-runner`, `z2p-deploy`, and `z2p-release` know the new reviewers.
- Every new skill has trigger evals and was used once on a worked example checked with the tool's own validator.

## Later / Out of Scope
- Team roles, handoffs, sprint ceremonies
- A fixed tech stack or hosting provider
- Native Windows (symlinks need Developer Mode). WSL works today.
- Publishing the repo as a Claude Code plugin marketplace for other people
- Building a `.skill` zip from the repo to upload skills to claude.ai
- Global `~/.claude/CLAUDE.md`, hooks, status line, keybindings (none exist yet)
- MCP servers (`pdfcraft`, `the-watcher`): they use a local binary, localhost, and secrets. README lists them as manual steps.
- A scheduled night run of the reviewer agents. Nothing is scheduled on this PC yet.
- A migration skill. `schema-design` hands off to one, but it does not exist yet. Until then, `task-runner` writes migrations and `sql-review` checks them.
- Automatic scheduling of stage 10 (operate) runs
- DevOps, later: Kubernetes, HashiCorp Vault, Windows containers, .NET Framework 4.8 apps, the GitLab CI/CD components catalog, SCVMM or Azure, dedicated IIS and nginx skills, a release runbook skill, Proxmox (the lab in `~/elab` keeps its own files)

## Stack
| Part | Choice |
|------|--------|
| Format | Claude Code skills (`SKILL.md`) and subagents (`agents/*.md`) |
| Source of truth | This git repo |
| Install | `install.sh` symlinks each skill folder into `~/.claude/skills/` and `~/.agents/skills/` (Codex), and each agent into `~/.claude/agents/` |
| Checks | `evals/lint.sh` and `evals/test-install.sh`, run by GitHub Actions on Linux and macOS; `evals/run-trigger-evals.sh` by hand |
| Setup entry point | Project skill `.claude/skills/setup-claude-code/` |
| Shared settings | `settings/settings.json`, merged into `~/.claude/settings.json` |
| Platforms | Linux and macOS |
| Chain progress | `STATUS.md` in each project, written only by `z2p` |
| Chain artifacts | Markdown files in each project |
| DevOps: VMs | Packer (`hyperv-iso`) golden images; Terraform with the `taliesins/hyperv` provider; Ansible (`ansible.windows` over WinRM, SSH for Linux) |
| DevOps: apps | .NET 10 LTS (ASP.NET Core, xUnit); current Angular (standalone, signals); Docker multi-stage images in the GitLab registry |
| DevOps: pipeline | GitLab CI templates in one `ci-templates` project; runners picked by tag (`docker`, `windows`, `hyperv`); masked protected variables; GitLab-managed Terraform state |
| DevOps: deploy | msdeploy to IIS on Windows VMs; systemd and nginx on Linux VMs; Docker on Linux VMs |

## Structure
```
<this repo>/
  README.md                  set up on a new PC, update, manual steps
  CLAUDE.md                  what this repo is; "set up" → setup skill; editing rules
  REQUIREMENTS.md            what this repo must do, and how to check it
  PLAN.md, TASKS.md          this plan
  install.sh                 links skills/ into ~/.claude and ~/.agents (Codex), agents/ into ~/.claude
  evals/                     lint, install test, trigger evals
  .github/workflows/         CI: lint and install test on Linux and macOS
  .claude/skills/
    setup-claude-code/       project-only skill: runs the whole setup
  settings/settings.json     plugins, marketplaces, model, theme (no secrets)
  agents/                    reviewer agents: 8 today, plus powershell, gitlab-ci, dotnet, angular
  skills/
    existing: ansible-review, code-comments, docker-review, git-branch, git-commit,
      network-review, packer-review, plan-to-tasks, product-brief, project-planner,
      schema-design, sql-review, sql-writing, svelte, svelte-review, task-runner,
      terraform-review, web-security-review
    new: z2p (SKILL.md + CONVENTIONS.md), z2p-idea, z2p-validate,
      z2p-requirements, z2p-design, z2p-deploy, z2p-release, z2p-operate
    devops (Part C): terraform (+ references/hyperv.md), packer, powershell, powershell-review,
      ansible, gitlab-ci, gitlab-ci-review, dotnet, dotnet-review, angular, angular-review, docker

<a project made with the chain>/
  CLAUDE.md, STATUS.md
  IDEA.md, PRODUCT_BRIEF.md, VALIDATION.md, REQUIREMENTS.md, PLAN.md, DESIGN.md,
  TASKS.md, RELEASE.md, BACKLOG.md
```

### Setup flow on a new PC
1. `git clone <repo> && cd <repo> && claude`
2. Say "set up for Claude Code".
3. The setup skill checks prerequisites and runs `install.sh --dry-run`. It shows the result and asks what to do with any conflicts.
4. It runs `install.sh`, merges `settings/settings.json`, and asks you to restart Claude Code. The restart loads the skills and installs the plugins.
5. After the restart, it checks that every skill and agent loads.

To update: `git pull`. Edited skills update right away, because they are links. A new skill needs the setup run again, which is safe to repeat.

### Chain stages
| Stage | Skill | Writes | Gate (checked from the files) |
|-------|-------|--------|-------------------------------|
| 0 Start | `z2p` | `STATUS.md`, `CLAUDE.md` | Git repo, `STATUS.md`, and `CLAUDE.md` exist |
| 1 Idea (optional) | `z2p-idea` | `IDEA.md` | One problem and one target user named, or stage skipped because the user brought an idea |
| 2 Brief | `product-brief` | `PRODUCT_BRIEF.md` | All sections filled; riskiest assumption named |
| 3 Validate | `z2p-validate` | `VALIDATION.md` | Each risky assumption has evidence or is marked untested; `Decision: Go / Change / Stop`; **user said yes** |
| 4 Requirements | `z2p-requirements` | `REQUIREMENTS.md` | Every MVP item in the brief has at least one requirement; every Must requirement has testable acceptance criteria; every non-functional topic is answered or marked "not needed"; **user confirmed** |
| 5 Plan | `project-planner` | `PLAN.md` | MVP lists requirement IDs; Later section exists; stack chosen, including database engine and hosting; main entities named; every decision has Choice, Why, Alternatives; **user confirmed** |
| 6 Design | `z2p-design` (+ `schema-design`) | `DESIGN.md` | Every Must requirement is in a flow; every flow step maps to an interface; every entity from `PLAN.md` is modelled; every table has a grain and a primary key (or "no stored data"); the architecture says where each part runs; a permissions table exists if there are users; **user confirmed** |
| 7 Tasks | `plan-to-tasks` | `TASKS.md` | Stage 1 is the walking skeleton; every task has What, Why, How; every Must requirement is delivered by at least one task |
| 8 Build | `task-runner` | code, `TASKS.md` notes | All MVP tasks `[x]`; tests pass |
| 9 Release | `z2p-release` | `RELEASE.md` | Tests and CI green; every Must requirement's acceptance criteria checked; matching reviews run; no open high findings; MVP live where users get it and it works; rollback tried; backup restored once if there is data; **user said yes** |
| 10 Operate | `z2p-operate` | `BACKLOG.md` | Errors and uptime visible; an alert reaches the user; backlog started |

### REQUIREMENTS.md, PLAN.md, and DESIGN.md
`REQUIREMENTS.md` (stage 4) says **what the product must do, and how well**. It is the contract that the later stages are checked against. This repo's own `REQUIREMENTS.md` uses the same format.
1. **Users and roles:** each role and what it needs.
2. **Functional requirements:** one per heading, with an ID (`R1`, `R2`, …) and a priority (Must for the MVP, or Later). Each is a user story ("As a <role>, I can <action>, so that <benefit>") with acceptance criteria. Each criterion is a yes/no check that can become a test.
3. **Non-functional requirements:** IDs `N1`, `N2`, … Each one names how it will be checked. Topics: performance, availability, security, privacy and personal data, accessibility, platforms and devices, data retention and backup, scale, cost, compliance. Every topic is answered or marked "not needed".
4. **Constraints:** budget, deadline, required tech, the user's skills.
5. **Out of scope** and **open questions**.

`PLAN.md` (stage 5) decides **with what**: a stack of language, framework, database engine, auth, and hosting. The non-functional requirements drive these choices. The MVP section lists requirement IDs instead of repeating them. It names the main entities in one line each, because the database choice depends on the kind of data.

`DESIGN.md` (stage 6) decides **how the parts fit together**:
1. **User flows:** each main journey, step by step, naming the requirement IDs it covers.
2. **Architecture:** the parts (frontend, backend, database, background jobs, outside services), how they talk, and where each one runs. One Mermaid diagram.
3. **Entities:** each one's meaning in the domain and how it relates to the others.
4. **Database:** made with `schema-design`. For each table: the grain ("one row per ___"), primary key, columns and types, foreign keys, and the indexes the flows need. Also: which table grows fastest, and what must never be rewritten. Products with no stored data write "no stored data" instead.
5. **Interfaces:** pages or screens, API endpoints, or CLI commands, each with its input, output, and errors.
6. **Auth and permissions:** a table of who can do what to which data. `web-security-review` checks the code against it later.
7. **Cross-cutting:** config and secrets, error handling, migrations, logging.
8. **Folder layout.**
9. **Design decisions:** each with Choice, Why, Alternatives. Coach mode works here too.

If the product has a UI, `impeccable` designs the look, and `DESIGN.md` links to its output.

How later stages use them:
- `plan-to-tasks` turns tables, interfaces, and flows into tasks. Each task names the `DESIGN.md` section it builds and the requirement IDs it delivers.
- `task-runner` turns each delivered requirement's acceptance criteria into tests, and uses `sql-writing` for queries. A schema change during the build updates `DESIGN.md` with a "Changed:" line after asking the user, the same way `PLAN.md` changes are handled.
- `z2p-release` checks every Must requirement's acceptance criteria and records the results in `RELEASE.md`. It runs `sql-review` and `web-security-review` against the Database and Permissions sections.

**Walking skeleton:** the smallest version of the product that runs end to end in production, like a hello-world page or command. It has tests, CI, error tracking, and a rollback that has been tried once. If there is a database, it is created in production and the first migration runs through the pipeline. Every later task ships over this path.

**`STATUS.md` states:** `todo`, `doing`, `waiting` (with a reason, like "waiting for 3 interviews"), `done`, `skipped`, `stale`.

**Going back:**
- A Stop at stage 3 ends the project. The brief and validation are kept.
- A Change at stage 3 goes back to stage 2.
- Reopening an earlier stage marks every later `done` stage as `stale`. The orchestrator re-checks their gates before moving on.
- Stage 10 sends picked backlog items to stage 7. If an item adds a requirement, it goes to stage 4 instead; if it changes the plan, to stage 5. `STATUS.md` counts cycles.

**Rules for every stage skill** (full version in `CONVENTIONS.md`):
- Read the previous stage's file if it exists. Ask only for what is missing.
- Write one file, using the name from the table.
- Never touch `STATUS.md`. That way every stage skill still works alone.
- If `STATUS.md` exists, end with "run z2p for the next stage" instead of naming a skill.

## Decisions
### D1: Process is a skill chain
- **Choice:** One skill per stage, tied together by an orchestrator.
- **Why:** Matches the existing setup (brief, planner, tasks, runner, and reviewers are already skills).
- **Alternatives:** Written playbook only; both playbook and skills.

### D2: Cover every stage, without overlap
- **Choice:** The chain goes from idea to operate. Overlapping work is merged, so it needs 8 new skills, including the new requirements stage. The old plan needed 9 and had no requirements stage.
- **Why:** User wants a complete process, not gap-filling.
- **Alternatives:** Fill gaps only; only the pre-code stages.
- **Changed:** Setup is now part of the orchestrator, `coach-me` is a mode of `project-planner` (D9), and test and deploy are now `z2p-release`. Each overlap was another place for the skills to drift apart. A requirements stage was added (D16).

### D3: Solo use
- **Choice:** No team roles or ceremonies.
- **Why:** Keeps the process light.
- **Alternatives:** Small team with handoffs and sign-offs.

### D4: Product-agnostic
- **Choice:** No fixed stack. Stage 0 only creates git, `STATUS.md`, and a minimal `CLAUDE.md`. After stage 5, the orchestrator adds a "Skills for this project" line to `CLAUDE.md`. The release gate works for any product: a URL, a package registry, an app store, or a download.
- **Why:** The product type is open, and the stack is not known before stage 5.
- **Alternatives:** Web-app-only; web apps plus infra.
- **Changed:** Stage 0 used to ask for the product kind and pick skills to copy, before the stack was chosen. The deploy gate used to need a live URL, which a CLI tool or library does not have.

### D5: Orchestrator plus stage skills
- **Choice:** `z2p` tracks progress in `STATUS.md` and runs the next stage. It is the only thing that writes `STATUS.md`, and it checks gates by reading the stage files. It suggests `/clear` between stages, because the files carry the state.
- **Why:** One entry point, no lost place between sessions. With one writer, `STATUS.md` cannot disagree with itself, and stage skills stay usable alone.
- **Alternatives:** Independent skills run by hand; each stage skill updates `STATUS.md`.
- **Also:** With no `STATUS.md` but existing files or code, the orchestrator adopts the project. It marks every stage whose gate already passes as `done`, then asks the user to confirm.

### D6: The repo is the only source; install by symlink
- **Choice:** Every skill and agent lives in this repo. `install.sh` symlinks each folder into `~/.claude`. Projects do not get their own copies.
- **Why:** Copies drift. The installed `git-commit` had already moved ahead of the repo copy, and 3 skills and 8 agents were never in the repo at all. With links, editing a skill edits the repo, and `git pull` updates every PC.
- **Alternatives:** Copy files on install; template repo per project; per-project copies.
- **Changed:** The plan used to keep global skills plus per-project copies, which made several copies to maintain.
- **Changed (2026-11-04):** Codex reads the same skill folders through `~/.agents/skills`, so `install.sh` links them for both clients. Agents stay Claude-only.

### D7: Exit gate per stage
- **Choice:** One gate table in `CONVENTIONS.md`. Each gate can be checked by reading files. The go/no-go, requirements, plan, design, and release gates (3, 4, 5, 6, 9) also need a yes from the user. A gate can send the project back (see "Going back").
- **Why:** Catches a bad idea or a broken build early. When gates can be checked from files, the orchestrator can verify them instead of trusting a stage's own report.
- **Alternatives:** No gates; the gate copied into each stage skill.
- **Changed:** Gates used to be written in both the orchestrator and each stage skill, and the chain could only move forward.

### D8: Deploy early with a walking skeleton
- **Choice:** Hosting is decided in stage 5 (`project-planner` already asks about it). Stage 1 of every `TASKS.md` puts a hello-world version live with CI, error tracking, and a tried rollback. `z2p-deploy` is the helper skill for those tasks. It reuses `ci-pipelines`, `container-builds`, and the infra reviewers. Stage 9 releases the MVP over a path that already works.
- **Why:** Deploy problems like hosting, secrets, DNS, and rollback are cheapest to fix on day one, and most expensive after all the code is written.
- **Alternatives:** Deploy once at the end, with its own hosting decision.
- **Changed:** Deploy used to come after all development.

### D9: Coach mode inside `project-planner`
- **Choice:** `project-planner` gets a coach mode, turned on by "coach me" or "teach me". Each question explains why the recommended choice is best, what the alternatives cost, and when the recommendation would be wrong. The user can argue back, and the skill answers the objection before moving on. The final reasoning goes into each decision in `PLAN.md`. `z2p-design` and `z2p-deploy` support the same mode for their decisions.
- **Why:** The user wants to learn why each choice is best. A mode keeps one interview instead of two copies that drift apart. The explanation goes into the question text, so it does not use up one of the 4 answer slots.
- **Alternatives:** A separate `coach-me` skill; an "Explain" option on every question.
- **Changed:** This used to be a separate `coach-me` skill for the planning stage only.
- **Note:** "Coach" is my reading of "cockme". Rename it if you meant something else.

### D10: Tests with each task, reviews at the end of each task stage
- **Choice:** `task-runner` writes or updates tests with each task. When the last task of a `TASKS.md` stage is done, it runs the review skills that match the files changed in that stage. Stage 9 is the full final review, not the first one.
- **Why:** A finding is cheap to fix right after the code is written.
- **Alternatives:** All testing and review in one stage at the end.
- **Changed:** The Terraform, Packer, Ansible, network, and Svelte reviews now run through their reviewer agents, because those five review skills are turned off in Claude Code (T6.6). The other reviews still run as skills, and Codex, which has no agents, runs every review as a skill.

### D11: Clone, then "set up for Claude Code"
- **Choice:** A project skill in `.claude/skills/setup-claude-code/` runs the setup. It only exists while Claude is opened in this repo. The skill does the parts that need judgement: prerequisites, conflicts, settings merge, checks. `install.sh` does the links, so they work the same way every time.
- **Why:** The user wants to clone, open Claude, and ask. A script alone cannot ask about conflicts. Claude alone would do the links slightly differently each time.
- **Alternatives:** Plugin marketplace (official and works on Windows, but edits are not live and every skill name gets a prefix); script only; setup steps in `CLAUDE.md` (loaded into every session in this repo, even when you only want to edit a skill).

### D12: Prefix new stage skills with `z2p-`
- **Choice:** New stage skills are named `z2p-idea`, `z2p-design`, and so on. Each description says it is a z2p stage.
- **Why:** Plain names like `design`, `deploy`, or `monitor` would trigger on everyday requests and clash with `impeccable`, `schema-design`, `k8s-deploy`, and `observability`.
- **Alternatives:** Plain names.

### D13: Machine-specific things stay out of the repo
- **Choice:** The repo has no credentials, MCP servers, memory, history, or per-machine paths. `settings/settings.json` holds only shared keys: plugins, marketplaces, model, theme. Skills synced from claude.ai arrive when you log in, so the repo does not handle them.
- **Why:** These files hold secrets or only make sense on one machine.
- **Alternatives:** Copy all of `~/.claude`.

### D14: `product-brief` lives in the repo
- **Choice:** `product-brief` moves to `skills/` and is installed like the others. The claude.ai copy is removed so there are not two `product-brief` skills.
- **Why:** One home. The claude.ai copy still points to a `project-planning` skill that does not exist.
- **Alternatives:** Keep it only in claude.ai, so it also works in web chat, and upload a zip after every change.

### D15: The plan picks the stack; the design owns architecture, entities, and the database
- **Choice:** `PLAN.md` names the database engine and the main entities. `DESIGN.md` holds the architecture, the full entity and table model (made with `schema-design`), interfaces, and permissions. In the chain, `project-planner` keeps its Structure section to one line per entity and page.
- **Why:** Both skills used to cover entities and structure, so the same model would be written twice and drift. The data model is the most expensive part to change later, so it gets its own stage, a user sign-off, and the skill built for it.
- **Alternatives:** Data model inside `PLAN.md`; a separate `SCHEMA.md`.

### D16: A requirements stage between validation and planning
- **Choice:** A new stage 4, `z2p-requirements`, writes `REQUIREMENTS.md`. It holds user stories with IDs and acceptance criteria, non-functional requirements, and constraints. The IDs are used in the design, the tasks, and the release check. This repo has its own `REQUIREMENTS.md` in the same format.
- **Why:** The brief is short on purpose, and says a requirements document comes later, but no stage wrote one. Without acceptance criteria there is nothing concrete to test or release against. Non-functional needs like personal data, scale, or uptime should drive the stack choice, not follow it.
- **Alternatives:** Requirements inside `PLAN.md` (mixes the "what" with the "with what"); a longer brief (loses its 3-minute read); no requirements, only tasks.

### D17: One writing skill, one review skill, one reviewer agent per DevOps tool
- **Choice:** Every tool in the DevOps set gets a writing skill: `terraform`, `packer`, `powershell`, `ansible`, `gitlab-ci`, `dotnet`, `angular`, `docker`. Tools that already have a review skill and agent (terraform, packer, ansible, docker) keep them. The other four get `<tool>-review` and a `<tool>-reviewer` agent built like `agents/sql-reviewer.md`. Anthropic's built-in `terraform-iac`, `powershell`, `ci-pipelines`, and `container-builds` stay turned off; the repo's skills replace them.
- **Why:** The pattern already exists for SQL and Svelte. The writing skill shapes the code while it is written, the review catches what slipped through, and the agent runs that review without a session. The built-in skills cannot be edited to match Hyper-V, msdeploy, or the templates repo.
- **Alternatives:** Writing skills only (conventions without checks); review skills only (the conventions live nowhere); turning the built-ins back on (generic, not editable).

### D18: Hyper-V VMs come from a Packer image, then Terraform, then Ansible
- **Choice:** Packer builds a golden image on Hyper-V with the `hyperv-iso` builder: Windows with `autounattend.xml` and sysprep as the last step, Linux with autoinstall and cloud-init. Terraform creates VMs from that image with the `taliesins/hyperv` provider (WinRM to the host), state in GitLab. Ansible configures each VM after first boot. PowerShell runs only inside Packer provisioners and for what the provider cannot do. There is no separate Hyper-V skill: the provider lives in `terraform/references/hyperv.md`, the builder in `packer`, the Hyper-V module in `powershell`.
- **Why:** One state file and a plan before every apply, so drift is visible. The Packer and Terraform reviews already exist. A Hyper-V skill of its own would repeat the three tools' content.
- **Alternatives:** PowerShell `New-VM` scripts (no plan, no state); Terraform calling PowerShell through `local-exec` (state that does not match reality); SCVMM (not in the stack).

### D19: Three deploy paths, one pipeline shape
- **Choice:** Apps deploy with msdeploy to IIS on Windows VMs, as systemd services behind nginx on Linux VMs, or as Docker images from the GitLab registry on Linux VMs. The `dotnet` skill publishes for all three (a Web Deploy package, a framework-dependent folder with a unit file, a multi-stage Dockerfile). `gitlab-ci` has one deploy job template per path. `ansible` prepares the hosts: IIS and Web Deploy on Windows, nginx and systemd on Linux, the Docker engine. `docker` writes the Dockerfiles and compose files.
- **Why:** These are the apps that exist today. One path would mean migrating them first.
- **Alternatives:** Containers everywhere (IIS apps would need Windows containers or a rewrite); Kubernetes (Later).

### D20: .NET 10 LTS and current Angular, configured at run time
- **Choice:** .NET 10 LTS with ASP.NET Core and xUnit. The current Angular major with standalone components and signals. Angular reads its environment from a `config.json` served next to the app, not from build-time environment files. .NET reads `appsettings.json` plus environment variables.
- **Why:** Build once (D22) needs one artifact that serves every environment. .NET 10 is installed here, so the worked examples can be built.
- **Alternatives:** .NET 8 (older LTS, nothing gained); .NET Framework 4.8 (Later: MSBuild and Windows-only builds); Angular build-time environments (one build per environment).

### D21: Pipelines are a product: one central templates repo
- **Choice:** A `ci-templates` GitLab project holds the pipeline templates: build, test, package, deploy to IIS, Linux, and Docker, Terraform plan and apply, Packer build, Ansible run. An app repo's `.gitlab-ci.yml` includes one template pinned to a tag and sets a few variables (app kind, paths). Jobs select runners by tag only (`docker`, `windows`, `hyperv`). No runner names, host names, or environment values appear in an app repo; those are GitLab group and project variables.
- **Why:** The project must not know how CI is set up, because the number and kind of runners will change. A template change reaches every pipeline once.
- **Alternatives:** A copy of the pipeline in each repo (drift); the CI/CD components catalog (newer and nicer, but `include` works on every GitLab version; Later).

### D22: Build once, promote the same artifact
- **Choice:** Every commit builds and tests. A merge to `main` deploys the artifact to staging. A manual job, guarded by `resource_group` and protected refs, deploys that same artifact (same job artifact or same image digest) to production. A rollback is a redeploy of the previous artifact.
- **Why:** What was tested is what ships. Rollback needs no rebuild.
- **Alternatives:** A git tag that builds and deploys production (rebuilds instead of promoting); a pipeline per environment (hardest to keep in sync).

### D23: Secrets in GitLab variables, Terraform state in GitLab
- **Choice:** Masked, protected CI variables: group level for shared values, project level for app-specific ones. Terraform state in GitLab-managed state with locking. Ansible reads secrets from CI variables at run time and uses Ansible Vault only for files that must live in a repo. Packer gets the build password from a variable.
- **Why:** Nothing extra to run, locking is built in, and the variables are already where the jobs run.
- **Alternatives:** HashiCorp Vault (better rotation and audit, one more service; Later); state on a file share (no locking, two applies collide).

### D24: Ansible reaches Windows over WinRM and Linux over SSH
- **Choice:** The `ansible.windows` and `community.windows` collections over WinRM with Kerberos (NTLM only in a lab), or SSH where OpenSSH is already installed. Linux over SSH. One inventory written by Terraform output, as the `~/elab` lab does. The control node is a Linux Docker runner with `pywinrm` and Kerberos.
- **Why:** WinRM is the supported path for Windows and the existing Ansible layout carries over unchanged.
- **Alternatives:** SSH only (every Windows host needs OpenSSH first); DSC (another tool to learn).

### D25: Build order: VMs, then Ansible, then the app pipeline
- **Choice:** Stage 7 builds `terraform`, `packer`, `powershell`, and `powershell-review` with its agent. Stage 8 builds `ansible` and updates `ansible-review` for Windows hosts. Stage 9 builds `gitlab-ci`, `dotnet`, `angular`, `docker`, their reviews and agents, and wires the reviewers into the chain.
- **Why:** The VMs are what everything deploys onto, and two of the three VM tools already have reviews.
- **Alternatives:** The app pipeline first (deploys to today's VMs sooner); Ansible first.

### D26: Each skill is proven by trigger evals and one worked example
- **Choice:** Every new skill gets at least two prompts that should fire and two that should not (`evals/lint.sh` requires it). Each writing skill is used once on a small example in `evals/examples/<skill>/`, and the result is checked with the tool's validator where this PC can run it: `terraform validate`, `packer validate`, PSScriptAnalyzer under `pwsh`, `dotnet build` and `dotnet test`, `ng build`, `ansible-lint`, `docker build`, and GitLab's CI lint when a token is at hand. A Hyper-V apply cannot run here; it is checked on the Windows side later.
- **Why:** This PC can validate the syntax of every tool but cannot run Hyper-V. The worked example catches a skill that reads well but produces code that does not parse.
- **Alternatives:** Trigger evals only (a skill can trigger and still mislead); a full Hyper-V lab (not available here).
- **Changed:** Worked examples used to live in a temp folder and be thrown away. The first one, for `terraform`, drifted from its skill and was nearly lost with the session folder. Examples now live in `evals/examples/<skill>/`, and `evals/lint.sh` runs the validator on them when it is installed.
