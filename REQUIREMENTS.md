# Claude Code Setup and z2p Skill Chain: Requirements

Status: Draft | Date: 2026-10-28 | Confirmed: _(date, once you agree)_

This file says what the repo must do and how to check it. `PLAN.md` says how it is built. The test tasks (T1.7, T5.2) check every requirement here.

## Users and roles
| Role | Who | What they need |
|------|-----|----------------|
| Owner | Me, on any of my PCs | The same Claude Code setup everywhere, and one process to take a project from idea to production |

## Functional requirements

### Setup

#### R1: Set up a new PC (Must)
As the owner, I can clone the repo, open Claude in it, and say "set up for Claude Code", so that the new PC works like my current one.
Acceptance:
- [ ] After one restart, every skill in `skills/` and every agent in `agents/` is listed in Claude Code.
- [ ] The plugins in `settings/settings.json` are installed and turned on.
- [ ] The model and theme match `settings/settings.json`.
- [ ] The setup ends with a list of the manual steps left (claude.ai login, MCP servers).

#### R2: Safe to re-run (Must)
As the owner, I can run the setup again at any time, so that I never have to wonder whether it is safe.
Acceptance:
- [ ] A second run changes nothing and reports every item as already OK.

#### R3: Never destroys my files (Must)
As the owner, I can run the setup on a PC that already has its own skills or agents, so that nothing of mine is lost.
Acceptance:
- [ ] A file or folder already at a target is reported, not overwritten.
- [ ] It is replaced only after I say yes, and the old one is kept in `~/.claude/backups/`.

#### R4: Update with `git pull` (Must)
As the owner, I can pull the repo on any PC, so that every PC gets my latest skills.
Acceptance:
- [ ] An edited skill is live after `git pull`, without running the setup.
- [ ] A new skill appears after the setup runs again.
- [ ] A skill removed from the repo is unlinked by the next setup run.

#### R5: Edits are live and tracked (Must)
As the owner, I can edit a skill on any PC, so that I can improve it where I notice the problem.
Acceptance:
- [ ] Editing `skills/<name>/SKILL.md` changes Claude in the next session, with no install step.
- [ ] `git status` in the repo shows the edit.

#### R6: Settings merge keeps mine (Must)
As the owner, I can merge the shared settings on a PC that has its own, so that I keep that PC's own settings.
Acceptance:
- [ ] Keys in `~/.claude/settings.json` that the repo does not set are unchanged.
- [ ] A key with a different value changes only after I say yes.
- [ ] The old settings file is backed up first.

#### R7: Agents work for any username (Must)
As the owner, I can use the reviewer agents on a PC where my username is not `deb`, so that they work everywhere.
Acceptance:
- [ ] Each agent reads its skill when the home folder is not `/home/deb`.

### z2p chain

#### R8: One entry point that resumes (Must)
As the owner, I can say "zero to prod" in any project folder, so that I continue where I stopped, even in a new session after `/clear`.
Acceptance:
- [ ] The orchestrator reads `STATUS.md` and runs the right next stage.
- [ ] Nothing that a stage file already answers is asked again.

#### R9: Each stage skill works alone (Must)
As the owner, I can run any stage skill by itself, so that I can use only the part I need.
Acceptance:
- [ ] In a folder with no `STATUS.md`, `product-brief`, `project-planner`, `plan-to-tasks`, and `task-runner` work as they do today.
- [ ] A stage skill never creates or edits `STATUS.md`.

#### R10: Gates stop bad moves (Must)
As the owner, I can trust that a stage is only marked done when its work is really there, so that problems do not reach production.
Acceptance:
- [ ] A stage whose gate fails is not marked `done`.
- [ ] Gates 3, 4, 5, 6, and 9 also wait for my yes.
- [ ] Every gate result is written in `STATUS.md`.

#### R11: Going back (Must)
As the owner, I can stop, change course, or reopen an earlier stage, so that the process follows what I learn.
Acceptance:
- [ ] A Stop at validation ends the project and keeps its files.
- [ ] A Change at validation goes back to the brief.
- [ ] Reopening a stage marks every later `done` stage as `stale`, and their gates are checked again.

#### R12: Waiting for evidence (Must)
As the owner, I can leave validation open for days while I talk to people, so that the go/no-go rests on real evidence.
Acceptance:
- [ ] Validation can sit in the `waiting` state with a reason.
- [ ] The orchestrator asks whether the evidence has arrived before moving on.

#### R13: Adopt an existing project (Must)
As the owner, I can start the chain in a project that already has files or code, so that I do not redo work.
Acceptance:
- [ ] With no `STATUS.md`, every stage whose gate already passes is marked `done` after I confirm.

#### R14: Coach mode (Must)
As the owner, I can ask to be coached through planning, so that I learn why each choice is best.
Acceptance:
- [ ] Every question explains why the recommendation is best, what the alternatives cost, and when the recommendation would be wrong.
- [ ] When I argue back, my objection is answered before moving on.
- [ ] The final reasoning is written in the `PLAN.md` decisions.

#### R15: Deploy on day one (Must)
As the owner, I can see a hello-world version live before the real features are built, so that deploy problems show up early.
Acceptance:
- [ ] When a host is chosen, Stage 1 of every `TASKS.md` deploys a hello-world version with CI, error tracking, the database (if any), and a tried rollback.

#### R16: Requirements are traced to the end (Must)
As the owner, I can see that every Must requirement of a project was designed, built, and checked, so that nothing is forgotten.
Acceptance:
- [ ] Every Must requirement in a project's `REQUIREMENTS.md` is covered by a flow in `DESIGN.md`.
- [ ] Every Must requirement is delivered by at least one task in `TASKS.md`.
- [ ] `RELEASE.md` shows a pass or fail for every Must requirement's acceptance criteria.

## Non-functional requirements
| ID | Topic | Requirement | How we check it |
|----|-------|-------------|-----------------|
| N1 | Security | No secrets, tokens, or machine-specific paths in the repo | `evals/lint.sh` searches for `/home/` paths and secret-like values; CI runs it |
| N2 | Platforms | Works on Linux and macOS; Windows through WSL | `evals/test-install.sh`, run by CI on Linux and macOS |
| N3 | Dependencies | `install.sh` needs only bash, git, and standard tools found on both Linux and macOS | Read the script; `evals/test-install.sh` runs it on both in CI |
| N4 | Speed | Setup on a new PC takes under 10 minutes, not counting the Claude Code install | Time it in T1.7 |
| N5 | Triggering | New skills fire on their own prompts, and not on unrelated ones | `evals/run-trigger-evals.sh` (T5.1, T6.4) |
| N6 | Style | Skills are short, in plain English, and match the existing ones | Read each new skill against an existing one |
| N7 | Cost | The chain itself needs no paid service. A project may still choose paid hosting. | Read the skills |
| N8 | Data retention and backup | The repo is the backup. Every change is committed and pushed to the remote. | `git status` is clean and pushed after each stage of `TASKS.md` |
| N9 | Privacy and personal data | Not needed: the repo stores no personal data | — |
| N10 | Performance, availability, scale, accessibility, compliance | Not needed: nothing runs as a service | — |

## Constraints
- Solo use. One person builds and uses it.
- Only Claude Code features: skills, subagents, settings, and a shell script.
- Switching this PC to the links must not lose the current skills or agents. T1.6 backs them up first.

## Out of scope
See "Later / Out of Scope" in `PLAN.md`.

## Open questions
- ~~Is "coach" the right name?~~ Answered: yes. `project-planner` and `z2p` both call it coach mode.
- Which second PC or user account will T1.7 use?
- ~~Can agent frontmatter preload a skill?~~ Answered: yes. Every agent in `agents/` lists its skill under `skills:`, and the agents load (T1.2).
