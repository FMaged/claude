# Worked examples

One small project per writing skill, written by following the skill (D26). They stay in
the repo so they can be checked again after the skill changes. Keep each one in line with
its skill: a fix to a snippet in the skill is a fix here too.

| Example | Skill | Checked with | Last result |
|---|---|---|---|
| `terraform/` | `terraform` and `references/hyperv.md` | `terraform fmt -check -recursive`, then `terraform init -backend=false` and `terraform validate` in `infra/envs/staging` | Passed 2026-11-15 with Terraform 1.17.2 |
| `packer/` | `packer` | `packer fmt -check -recursive`, then `packer init` and `packer validate` in each image folder | Passed 2026-11-15 with Packer 1.16.2 |
| `powershell/` | `powershell` | `evals/check-powershell.ps1`: PSScriptAnalyzer on every example script (the Packer provisioner scripts too), then the Pester tests | Passed 2026-11-15 with PowerShell 7.7, PSScriptAnalyzer 1.25.0, Pester 6.2.0 |
| `hyperv-deploy/` | `hyperv-deploy` | `evals/check-powershell.ps1`: PSScriptAnalyzer on the two scripts, the module, and the data file, then 24 Pester tests with the Hyper-V and Storage cmdlets mocked | Passed 2026-11-15 with PowerShell 7.7, PSScriptAnalyzer 1.25.0, Pester 6.2.0 |
| `ansible/` | `ansible` | `ansible-lint`, then `ansible-playbook -i inventory/staging playbooks/app.yml --syntax-check` | Validated locally with ansible-core 2.19.11 and ansible-lint 25.6.1; requires approved installer URLs, SHA-256 checksums, and the Hosting Bundle uninstall key before a host run |
| `gitlab-ci/` | `gitlab-ci` | `yamllint --strict`, then `evals/check-gitlab-ci.py` merges each template and the app's file as GitLab would (includes, `extends`) and checks tags, stages, and `needs`, then `check-jsonschema --builtin-schema vendor.gitlab-ci` on the merged result | Passed 2026-11-16 with yamllint 1.38.0 and check-jsonschema 0.39.0; also valid against GitLab 19.5.5's own `ci.json`. No GitLab instance or token was used, so nothing ran on a runner |
| `dotnet/` | `dotnet` | `dotnet test` and `dotnet publish` at the example root, then `docker build` | Not built yet: written 2026-11-16 without running anything. It has no `packages.lock.json` files until the first `dotnet restore`, so the locked-mode restore and the Docker build fail until they are committed. Not in `evals/lint.sh` |
| `angular/` | `angular` | `npm ci`, `npx ng lint`, `npx ng test --configuration ci`, and `npx ng build` at the example root, then `docker build` | Not built yet: written 2026-11-16 without running anything; versions read from the npm registry that day. It has no `package-lock.json` until the first `npm install`, so `npm ci` and the Docker build fail until it is committed. A browser call to the `dotnet/` API also needs a CORS policy there, which it does not have yet. Not in `evals/lint.sh` |
| `docker/` | `docker` | `hadolint` and `docker build` on `../dotnet/Dockerfile`, then, with `orders.env.example` copied to `orders.env`, `IMAGE=<that image> docker compose config` and `docker compose up --detach --wait` | Not built yet: written 2026-11-16 without running anything. The image needs the `dotnet/` lock files first. Not in `evals/lint.sh` |
| `bash/` | `bash` | `shellcheck` on both scripts, then `test-fetch-tool.sh`, which runs `fetch-tool.sh` 11 times against local archives and makes 17 checks (each mode, a second run, bad input, a wrong checksum, a zip) | Passed 2026-11-15 with Bash 5.2 and ShellCheck 0.10.0 |

`evals/lint.sh` runs these checks when the tool is installed and skips them otherwise.
CI installs Terraform 1.17.2, Packer 1.16.2, PSScriptAnalyzer, Pester, and ShellCheck (on Linux), so they always run there. The Bash test needs only curl, tar, unzip, and python3, which both runners have.
Nothing here is applied or built: a Hyper-V apply or image build needs a host (see T7.5).
