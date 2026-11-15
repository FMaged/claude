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

`evals/lint.sh` runs these checks when the tool is installed and skips them otherwise.
CI installs Terraform 1.17.2, Packer 1.16.2, PSScriptAnalyzer, and Pester, so they always run there.
Nothing here is applied or built: a Hyper-V apply or image build needs a host (see T7.5).
