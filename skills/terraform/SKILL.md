---
name: terraform
description: Use when writing or changing Terraform or OpenTofu code — a module, a root module per environment, variables and validation, outputs, for_each, the provider and version pins, the lock file, the GitLab state backend, or VMs on Hyper-V with the taliesins/hyperv provider (e.g. "write a terraform module for a VM", "add a variable", "set up the terraform state in GitLab", "create Hyper-V VMs with terraform", "feed the ansible inventory from terraform", "why does terraform want to recreate everything"). For reviewing Terraform code or a plan, use terraform-review instead.
---

# Terraform

Write it so `terraform plan` tells the truth: every change it shows is one you meant, and
nothing changes that it did not show. Most Terraform trouble is a plan that surprises
someone — a resource replaced because a list shifted, a value that lives outside the code,
two applies racing on one state.

For Hyper-V VMs, read `references/hyperv.md` before writing a VM resource. For a review of
finished code or a plan, use `terraform-review`. For comments, `code-comments`.

## 0. Check what is installed

Run `terraform version` (or `tofu version`) and read `versions.tf` and
`.terraform.lock.hcl` first. Write for the version the project pins. Features named
here and their minimum version: `optional()` attributes with defaults (1.3),
`terraform_data` (1.4), `removed` blocks (1.7), ephemeral variables and resources
(1.10), write-only arguments (1.11). On an older version, say what is missing instead
of writing code that will not parse.

## 1. Layout: one root module per environment, one module per thing

```
infra/
  modules/
    hyperv-vm/            # one thing: a VM with its disk and first-boot seed
      main.tf variables.tf outputs.tf versions.tf
  envs/
    staging/              # one root module = one state = one environment
      versions.tf backend.tf providers.tf main.tf variables.tf outputs.tf inventory.tf
      terraform.tfvars    # this environment's values, nothing secret
    prod/
```

- A root module is an environment. It calls modules, and its committed
  `terraform.tfvars` holds that environment's values (the VM map, sizes, switch names).
  It is the only place with a `provider` block and a `backend`.
- A module is one thing that is created together and destroyed together. No `provider`
  block, no backend, no environment names inside it.
- Staging and prod differ only in the values they pass. If prod needs a resource staging
  does not have, that is a module input (`enabled`, a map that can be empty), not a copy
  of the module.
- Nothing secret or personal in a committed `.tfvars`. Secrets come from `TF_VAR_*`
  environment variables set by masked CI variables; list them in the root's README or
  in the variable descriptions, so a local run knows what to export.
- No workspaces for environments. Separate root modules make the environment visible in
  the path and in the state name, and a typo cannot apply staging values to prod.

## 2. Versions and the lock file

- `required_version` in every root module. In a root module pin each provider exactly
  (`version = "= 1.2.1"`); in a reusable module give a minimum (`">= 1.2.0"`) so the
  root decides.
- Commit `.terraform.lock.hcl`. It is the record of which provider binary was tested.
- Lock for every platform that runs Terraform, or the first run elsewhere rewrites the
  file: `terraform providers lock -platform=linux_amd64 -platform=windows_amd64`.
- CI runs `terraform init -lockfile=readonly`, so a provider change goes through a
  commit, not through a pipeline run.
- A module from another repo is pinned to a tag: `git::https://…//modules/hyperv-vm?ref=v1.4.0`.
  A module in the same repo is a relative path and needs no pin.

## 3. Variables

Every variable has a `type` and a `description`, and a `validation` wherever a wrong value
would fail late (in the middle of an apply, or on the host) instead of at plan time.

```hcl
variable "vms" {
  description = "VMs in this environment, keyed by VM name. The key becomes the Hyper-V name and the hostname."
  type = map(object({
    image     = string                 # golden image file name, for example win2025-20261115-a1b2c3d.vhdx
    os        = string                 # "windows" or "linux"
    role      = string                 # Ansible group, for example "web" or "db"
    cpus      = optional(number, 2)
    memory_gb = optional(number, 4)
    vlan_id   = optional(number)
    mac       = optional(string)       # only when a DHCP reservation needs it
  }))

  validation {
    condition     = alltrue([for name, vm in var.vms : can(regex("^[a-z][a-z0-9-]{0,14}$", name))])
    error_message = "VM names must be lowercase, start with a letter, and be at most 15 characters (the NetBIOS limit)."
  }

  validation {
    condition     = alltrue([for vm in values(var.vms) : contains(["windows", "linux"], vm.os)])
    error_message = "os must be \"windows\" or \"linux\"."
  }

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      can(regex("^[a-z][a-z0-9_]*$", vm.role)) && !contains(["windows", "linux"], vm.role)
    ])
    error_message = "role is an Ansible group name: lowercase letters, digits, and _, and not windows or linux."
  }
}
```

- An `object` with `optional()` attributes, not a `map(any)`: a typo in an attribute name
  is an error instead of a silently ignored key.
- A secret is `sensitive = true`. If it is used only in a `provider` block or a
  write-only argument, also `ephemeral = true` (1.10+), and it never reaches the plan
  file or the state.
- No default for anything that differs per environment. A missing value should stop the
  plan, not quietly pick staging's value.
- No variable for something that never changes. A constant is a `local`.

## 4. `for_each` keyed by name, never `count` over a list

```hcl
module "vm" {
  source   = "../../modules/hyperv-vm"
  for_each = var.vms

  name      = each.key
  image     = each.value.image
  # …
}
```

- `count = length(var.list)` addresses resources by position. Remove the second item and
  every item after it is destroyed and recreated. Key by a stable name with `for_each`,
  and a removal touches only what was removed.
- `count` is for one thing that exists or does not: `count = var.enabled ? 1 : 0`.
- The `for_each` key must be known at plan time: a name from a variable, never an id an
  apply creates.
- Renaming a key or moving a resource into a module is a destroy and a create unless you
  say otherwise. Add a `moved` block and check that the plan shows `has moved to`, not
  `must be replaced`:

  ```hcl
  moved {
    from = hyperv_machine_instance.web["web01"]
    to   = module.vm["web01"].hyperv_machine_instance.this
  }
  ```

- To stop managing something without destroying it, use a `removed` block with
  `lifecycle { destroy = false }` (1.7+), not `terraform state rm` by hand.

## 5. Resources

- Let references carry the order. `depends_on` only where no reference can, and then a
  comment says why.
- `lifecycle { prevent_destroy = true }` on anything that holds data you cannot rebuild
  (a data disk, a database). It cannot come from a variable, so keep data in its own
  resource and leave rebuildable things (an OS disk from an image) without it.
- `ignore_changes` only for an attribute something else owns by design, with a comment
  naming the owner. Never to quiet a diff you do not understand.
- No `local-exec` or `remote-exec` to configure a machine. Terraform creates the VM;
  first boot (cloud-init or unattend) and Ansible configure it. A provisioner's
  result is not in state, so the plan cannot see when it drifts.
- Names that will be read by a human (VMs, disks, switches) come from the key, so the
  host and the code use the same name.

## 6. Outputs and the Ansible inventory

Terraform knows which hosts exist, so it writes the inventory and Ansible never keeps a
copy. The VM module gives what the inventory needs:

```hcl
# modules/hyperv-vm/outputs.tf
output "fqdn" {
  description = "Name Ansible connects to. Kerberos needs the name, not the address."
  value       = "${var.name}.${var.domain}"
}

output "os" {
  description = "windows or linux."
  value       = var.os
}

output "role" {
  description = "Ansible group, for example web or db."
  value       = var.role
}
```

The root module puts each host in two groups: its OS, for the connection settings
(`group_vars/windows.yml` sets WinRM), and its role, for what it runs
(`group_vars/web.yml`).

```hcl
# envs/staging/inventory.tf
locals {
  vms   = values(module.vm)
  roles = distinct([for vm in local.vms : vm.role])

  inventory = {
    all = {
      children = merge(
        {
          for os in ["windows", "linux"] : os => {
            hosts = { for vm in local.vms : vm.fqdn => {} if vm.os == os }
          }
        },
        {
          for role in local.roles : role => {
            hosts = { for vm in local.vms : vm.fqdn => {} if vm.role == role }
          }
        },
      )
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory/${basename(abspath(path.module))}.yml"
  file_permission = "0644"
  content         = yamlencode(local.inventory)
}
```

- Build the structure in `locals` and write it with `yamlencode`. It is valid YAML for an
  empty map and needs no template. Use `templatefile` only when the file needs comments
  or an exact layout, and then check it renders with zero and one host.
- Windows hosts reached over WinRM with Kerberos need `ansible_host` to be the FQDN:
  Kerberos tickets are issued for names, not addresses.
- No secret in the inventory. Connection secrets reach Ansible as CI variables.
- The inventory file is generated: say so in `.gitignore` or in a header, and never edit
  it by hand.
- In CI the file does not exist in a fresh clone, so every plan shows `local_file` as
  created. That is expected. The apply job passes the file to the Ansible job as an
  artifact.
- Mark an output `sensitive = true` if it contains anything a log should not show.

## 7. State in GitLab

GitLab-managed state, with locking, one state per root module.

```hcl
terraform {
  backend "http" {}
}
```

The empty block is filled from environment variables, so no address or token is written
in the code. In the CI template:

```yaml
variables:
  TF_STATE_NAME: staging     # one per root module: staging, prod
  TF_HTTP_ADDRESS: ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${TF_STATE_NAME}
  TF_HTTP_LOCK_ADDRESS: ${TF_HTTP_ADDRESS}/lock
  TF_HTTP_UNLOCK_ADDRESS: ${TF_HTTP_ADDRESS}/lock
  TF_HTTP_LOCK_METHOD: POST
  TF_HTTP_UNLOCK_METHOD: DELETE
  TF_HTTP_USERNAME: gitlab-ci-token
  TF_HTTP_PASSWORD: ${CI_JOB_TOKEN}
  TF_HTTP_RETRY_WAIT_MIN: "5"
```

- A local run uses the same variables with your GitLab user name and a personal access
  token with the `api` scope as `TF_HTTP_PASSWORD`.
- Writing state and taking the lock need the Maintainer role. The job token acts as the
  user who started the pipeline, so a merge request opened by a Developer plans with
  `-lock=false` (read only).
- State holds every resource argument in clear text, including anything `sensitive`.
  Only provider configuration, ephemeral values, and write-only arguments stay out.
- Never edit state by hand. `moved`, `removed`, and `import` blocks are reviewed in a
  merge request; `terraform state` commands are not.

## 8. The pipeline: plan on a merge request, apply on `main`

The jobs live in the `ci-templates` repo. What a Terraform job runs:

```
terraform fmt -check -recursive
terraform init -input=false -lockfile=readonly
terraform validate
terraform plan -input=false -out=plan.cache        # merge request: add -lock=false
terraform apply -input=false plan.cache            # main only, the plan from the same pipeline
```

- A merge request runs plan only and shows the plan in the merge request. Nothing is
  applied from a branch.
- On `main`, plan and apply are two jobs. Apply uses the saved `plan.cache` from the plan
  job of the same pipeline, so what was reviewed is what runs. If the state changed in
  between, apply refuses the stale plan; run the pipeline again.
- Staging applies on merge. Prod applies from a manual job with `resource_group` so two
  applies never run at once.
- The plan file holds secrets in clear text. Give the artifact a short `expire_in`.
- Never `-auto-approve` without a saved plan. `apply plan.cache` needs no approval
  because the plan was the approval.
- The jobs run on the `docker` runner tag and reach the Hyper-V host over WinRM. The
  provider credentials are CI variables (`HYPERV_USER`, `HYPERV_PASSWORD`, and so on),
  never `provider` arguments.

## 9. Style

- `terraform fmt` decides formatting. Do not argue with it.
- Files by purpose: `versions.tf`, `backend.tf`, `providers.tf`, `variables.tf`,
  `outputs.tf`, `main.tf`, and one file per concern when `main.tf` grows (`inventory.tf`).
- Resource names say what the thing is in this module, not its type again:
  `hyperv_machine_instance.this` in a one-VM module, `hyperv_vhd.data` for its data disk.
- Comment the why (a provider quirk, a value forced by the host), never what the block
  obviously does. Follow the `code-comments` skill.

## Before calling it done

```
terraform fmt -check -recursive
terraform init -backend=false && terraform validate     # in every root module
terraform plan -out=plan.cache && terraform show plan.cache
```

Read the plan line by line. Every `must be replaced` needs a reason you can say out loud,
and `0 to destroy` is the answer you expect for most changes. On Hyper-V, every
`~ update in-place` of a `hyperv_machine_instance` is a reboot. Then run
`terraform-review` on the change.
