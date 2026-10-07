---
name: ansible-review
description: Use when reviewing Ansible playbooks, roles, inventory, or Jinja templates (e.g. "review this playbook", "check my role", "why isn't this idempotent?", "look at these tasks"). Reports what is not idempotent, what could lock you out, and what leaks secrets, with the file and line.
---

# Ansible Review

Review playbooks, roles, `group_vars`, and `.j2` templates. Report problems. Do not rewrite unless the user asks.

## 1. Idempotency

Run it twice; the second run should change nothing.

- `command` or `shell` without `creates`, `removes`, or `changed_when`. Every run reports changed, so you can never trust the output.
- A read-only `command` without `changed_when: false`.
- `state: latest` on a package. It changes on someone else's schedule. Use `present`, or pin the version.
- `lineinfile` or `replace` where a template would own the whole file.
- Appending to a file with `shell` and `>>`.
- A module doing the job of a real module: `shell: systemctl ...` instead of `systemd`, `shell: nft ...` instead of a templated ruleset, `shell: apt-get ...` instead of `apt`.

## 2. Locking yourself out

This is the one that costs an afternoon. Check any task touching SSH, the firewall, or the network.

- An sshd config change without `validate: /usr/sbin/sshd -t -f %s`.
- An nftables or iptables ruleset applied without a syntax check first (`nft -c -f %s`), and without the management port allowed in the same ruleset.
- A firewall default-deny applied before the allow rules, or in a separate play that can fail in between.
- A network or interface change with no way back if it is wrong.
- Handlers that restart the network or sshd: check what happens when the handler runs but the config is bad.

## 3. Secrets

- A password, token, or key in plain text in `defaults`, `vars`, or inventory. It belongs in Vault or in an environment variable.
- A task that would print a secret in its output and has no `no_log: true`.
- A private key copied to a host with default permissions instead of `mode: "0600"`.

## 4. Structure

- Fully qualified module names (`ansible.builtin.copy`, not `copy`).
- Every task has a `name` that says what it does.
- `defaults/main.yml` for anything overridable, `vars/main.yml` only for constants that must win.
- Variables prefixed with the role name, so two roles cannot collide.
- No duplicated literal value (an IP, a port, a path) in several roles. It belongs in `group_vars`.
- `become` on the task or block that needs it, not on the whole play by habit.
- `loop`, not the old `with_items`.
- Roles do one thing. A role named for a machine rather than a job is a smell.

## 5. Templates

- Every variable either has a default (`| default(...)`) or is genuinely required, and a missing one fails with a clear message.
- Values that could contain a space or a quote are quoted in the output.
- A config file template has a `validate` on the task where the tool offers one.
- Loops over a list render correctly when the list is empty or has one item.
- The generated file says it is generated and should not be hand-edited.

## 6. Ordering and reruns

- A play that depends on the previous play's handler having run needs `meta: flush_handlers`.
- Staged rollouts: check the wait condition is a real one (the service answering, the route being there), not `pause` with a guessed number of seconds.
- Does it still work against a host that is already configured, and against a fresh one?

## Commands

```
ansible-lint
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/site.yml --check --diff
```

`--check` only means something if the tasks are check-safe. Note any `shell` task that would be skipped in check mode and so hide a failure.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it breaks>
Fix: <the change, one line>
```

Say plainly which findings would break a run and which are tidiness. If it is fine, say so in a sentence. If you add a comment as part of a fix, follow the `code-comments` skill.
