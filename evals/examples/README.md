# Worked examples

One small project per writing skill, written by following the skill (D26). They stay in
the repo so they can be checked again after the skill changes. Keep each one in line with
its skill: a fix to a snippet in the skill is a fix here too.

| Example | Skill | Checked with | Last result |
|---|---|---|---|
| `terraform/` | `terraform` and `references/hyperv.md` | `terraform fmt -check -recursive`, then `terraform init -backend=false` and `terraform validate` in `infra/envs/staging` | Passed 2026-11-15 with Terraform 1.17.2 |

`evals/lint.sh` runs these checks when the tool is installed and skips them otherwise.
CI installs Terraform 1.17.2, so they always run there.
Nothing here is applied: a Hyper-V apply needs a host (see T7.5).
