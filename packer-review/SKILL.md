---
name: packer-review
description: Use when reviewing Packer templates or image builds (e.g. "review my packer template", "check this .pkr.hcl", "why is this image not reproducible?", "look at the build"). Reports what is baked into the image that should not be, what is unpinned, and what is left dirty.
---

# Packer Review

Review `.pkr.hcl` files, their variables, and the provisioner scripts they run. Report problems. Do not rewrite unless asked.

## 1. What ends up in the image

An image is copied to every machine, so anything left in it is left everywhere.

- **Secrets.** An API token, password, or private key written during the build and not removed. Check it is not in a file, in a shell history, in `cloud-init` logs, or in an environment file.
- **SSH keys.** The build key in `authorized_keys`, and the host keys. Host keys must be removed so each clone generates its own, otherwise every machine shares an identity.
- **Machine identity.** `/etc/machine-id` emptied (not deleted), so clones do not share one and DHCP does not hand them the same lease.
- **Cloud-init state.** `cloud-init clean --logs` at the end, or first boot on a clone does nothing.
- **Leftovers.** `apt` lists and caches, `/var/log`, `/tmp`, `~/.bash_history`, the uploaded provisioner scripts themselves.

## 2. Pinning and reproducibility

- `required_plugins` with a pinned version, and `packer init` run.
- The source ISO or base image pinned, with a real `iso_checksum`. Never `none`.
- Package versions pinned where a drift would matter. If not pinned, say so plainly: the build is "whatever upstream had that day", which is a choice, not a bug.
- A `manifest` post-processor so you know later which build produced which image.

## 3. Shell provisioners

- `set -euo pipefail` at the top of every script. Without `-e`, a failed command in the middle leaves a broken image that builds successfully.
- A long `inline` block that should be a script file.
- `sleep` used where a real wait condition exists.
- A reboot in the middle without a following `pause_before` or a wait for SSH to come back.
- A command that needs sudo but has no `execute_command` or `sudo` prefix.

## 4. Source block

- `ssh_password` or a plain credential in the file instead of a sensitive variable or an environment variable.
- `ssh_timeout` long enough for a slow install, and `headless` set for a CI build.
- A `boot_command` that depends on typing timing. It is the most fragile part of any Packer build. Prefer an autoinstall, kickstart, or cloud-init seed file.
- Disk size, memory, and CPU sized for the build, and noted if they carry into the clone.

## 5. Where the line sits

Decide what belongs in the image and what belongs in configuration management, and say when a template crosses it. Packages and hardening that every machine needs belong in the image. Anything host-specific (addresses, roles, service config) belongs in Ansible or cloud-init, not baked in.

## Commands

```
packer init .
packer fmt -check .
packer validate .
packer build -on-error=ask .      # leaves the machine up to inspect
```

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it causes on a clone>
Fix: <the change, one line>
```

For anything left in the image, say what it leaks or breaks when the image is used twice. If it is clean, say so in a sentence.
