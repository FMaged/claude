---
name: terraform-review
description: Use when reviewing Terraform or OpenTofu code or a plan (e.g. "review my terraform", "check this .tf", "is this plan safe to apply?", "look at the module"). Reports what would break, what is unsafe to apply, and what is unpinned, with the file and line.
---

# Terraform Review

Review `.tf`, `.tfvars`, and plan output. Report problems. Do not rewrite the code unless the user asks.

## 1. Is it safe to apply

The most useful thing you can say. Check these first:

- **Replacements.** Run a plan and look for `must be replaced` and `forces replacement`. Name every resource that gets destroyed and say what is lost with it (a disk, an IP, data, state on the machine).
- **Destroy risk.** Anything stateful (volume, database, disk) without `lifecycle { prevent_destroy = true }`.
- **Downtime.** A resource that others depend on being replaced without `create_before_destroy`.
- **`-auto-approve`** in a path that touches anything real. Fine in a throwaway lab, never in shared or production infrastructure.
- **Count reindexing.** `count` over a list means inserting or removing an item shifts every index after it and recreates those resources. Use `for_each` keyed by a stable name instead.

## 2. Secrets and state

- Credentials, tokens, passwords, or private keys written in `.tf` or in a committed `.tfvars`.
- A real `terraform.tfvars` not in `.gitignore` (only the `.example` belongs in git).
- Outputs that expose a secret without `sensitive = true`.
- State: remote with locking for anything shared, and remember state holds secrets in clear text, so check it is not committed or world-readable.
- `local_file` writing a secret, or writing with default permissions when it needs `file_permission = "0600"`.

## 3. Pinning

- `required_version` set.
- Every provider pinned in `required_providers` (`=` or `~>`, never open).
- `.terraform.lock.hcl` committed.
- Module `source` pinned to a tag or commit, not a branch.

## 4. Structure

- Variables have a `type`, a `description`, and a `validation` block where a wrong value would fail late and confusingly (a CIDR, a size, a name length).
- No unused variables or outputs.
- No hardcoded ids, IP addresses, node names, or datastore names that belong in a variable.
- `depends_on` only where there is no implicit dependency. If a reference exists, the `depends_on` is noise.
- `lifecycle { ignore_changes }` hiding real drift.
- No `provider` block inside a reusable module.
- `templatefile` inputs: every variable the template uses is passed, and nothing is passed that it does not use.

## 5. Generated files

When Terraform generates config for another tool (an inventory, a flows file, a cloud-init file):

- The generated path is in `.gitignore`, or is clearly marked as generated.
- Nothing else hand-edits it.
- The template renders valid syntax when a list is empty or a map has one entry.

## Commands

```
terraform fmt -check -recursive
terraform validate
terraform plan -out=tf.plan && terraform show tf.plan
```

Skip style the formatter already fixes. Run `fmt -check` and say "formatting is off, run `terraform fmt`" in one line instead of listing it.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it breaks>
Fix: <the change, one line>
```

If the code is fine, say so in one sentence and name the two or three things you checked hardest. Do not invent findings to fill a list. If you add a comment as part of a fix, follow the `code-comments` skill.
