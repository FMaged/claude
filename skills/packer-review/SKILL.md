---
name: packer-review
description: Use when reviewing Packer templates or image builds (e.g. "review my packer template", "check this .pkr.hcl", "why is this image not reproducible?", "look at the build", "check my Windows golden image"). Reports what is baked into the image that should not be, what is unpinned, and what is left dirty, including a Windows image's sysprep, answer files, and build WinRM.
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

## 2. Windows images

A clone's first boot is driven by the answer file its deploy provides: Terraform's seed ISO, or the file `hyperv-deploy` writes. The image must not get in the way of it, and must not keep the doors the build opened. The writing rules are in the `packer` skill, section 5.

- **Sysprep missing or not last.** `sysprep.exe /generalize /oobe` must run in the last provisioner. Without `/generalize`, every clone keeps the build VM's identity (its SID, its KMS client id). A provisioner after it changes an image that is already generalized, and a reboot after it runs OOBE on the build VM.
- **Sysprep not waited for.** `sysprep.exe` is a GUI program: called with `&`, PowerShell returns at once. It needs `Start-Process -Wait`, then a check that the `ImageState` under `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State` reads `IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE`; without it a failed sysprep still produces an image. Sysprep in `shutdown_command` hides its failure from Packer the same way.
- **An answer file left in `C:\Windows\Panther`.** Setup copies the build's `Autounattend.xml` there during the install, and reads Panther before any removable media. Unless the last provisioner deletes `unattend.xml` and `autounattend.xml` from Panther, every clone ignores the seed ISO and boots with the build's settings. `sysprep /unattend:` caches yet another answer file there.
- **The build's WinRM left open.** `AllowUnencrypted = true`, the build's firewall rule for 5985, or Basic authentication still there after the build: every clone accepts unencrypted WinRM. The `shutdown_command` should undo them; a provisioner cannot, because it would cut its own connection. Connect with `winrm_use_ntlm = true`, so Basic stays off.
- **The build account.** A user made for the build and not removed. If the build logs on as Administrator, that password stays until the clone's first boot sets a new one, so it must be used for nothing else.
- **Windows Update with no `windows-restart` after it.** Sysprep refuses to run with a reboot pending, or the last update finishes on every clone instead.
- **The password from a literal.** The build or Administrator password written in the template, a `.pkrvars.hcl`, or a committed `Autounattend.xml`, instead of a sensitive variable set from `PKR_VAR_` and filled in with `cd_content` and `templatefile`. With no `validation` that rejects `<`, `>`, and `&`, such a password breaks the XML and Setup stops at its first page. A real product key is a secret too; the public KMS client keys are not.
- **Provisioner scripts** that need PowerShell 7 or do not start with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`: they run in Windows PowerShell 5.1, and without `Stop` a failed step builds an image anyway. For the scripts themselves, use the `powershell-review` skill.

## 3. Linux images on Hyper-V

- **The Hyper-V daemons missing** from the autoinstall, preseed, or kickstart packages (`hyperv-daemons` on Debian and RHEL, `linux-cloud-tools-virtual` on Ubuntu): the guest never reports its address, so Packer waits for SSH until it times out, and so does Terraform's `wait_for_ips` on every clone. A provisioner is too late to add them.
- **The build user** not locked, or `/etc/sudoers.d/packer` left in the image.
- **The installer's leftovers** on Ubuntu: `99-installer.cfg`, `subiquity-disable-cloudinit-networking.cfg`, or the installer's netplan file left behind stops cloud-init from configuring the clone's network; `sshd_config.d/50-cloud-init.conf` keeps the build's password login.
- **The `ansible` provisioner** in a build that runs on the Windows Hyper-V host, where Ansible does not run. Use `ansible-local`, which runs inside the guest.

## 4. Pinning and reproducibility

- `required_plugins` with a pinned version, and `packer init` run.
- The source ISO or base image pinned, with a real `iso_checksum`. Never `none`.
- Package versions pinned where a drift would matter. If not pinned, say so plainly: the build is "whatever upstream had that day", which is a choice, not a bug.
- A `manifest` post-processor so you know later which build produced which image.

## 5. Shell provisioners

- `set -euo pipefail` at the top of every script. Without `-e`, a failed command in the middle leaves a broken image that builds successfully.
- A long `inline` block that should be a script file.
- `sleep` used where a real wait condition exists.
- A reboot in the middle without a following `pause_before` or a wait for SSH to come back.
- A command that needs sudo but has no `execute_command` or `sudo` prefix.

## 6. Source block

- `ssh_password` or a plain credential in the file instead of a sensitive variable or an environment variable.
- `ssh_timeout` long enough for a slow install, and `headless` set for a CI build.
- A `boot_command` that depends on typing timing. It is the most fragile part of any Packer build. Prefer an autoinstall, kickstart, or cloud-init seed file.
- Disk size, memory, and CPU sized for the build, and noted if they carry into the clone.

## 7. Where the line sits

Decide what belongs in the image and what belongs in configuration management, and say when a template crosses it. Packages and hardening that every machine needs belong in the image. Anything host-specific (addresses, roles, service config) belongs in Ansible or cloud-init, not baked in.

## Commands

```
packer init .
packer fmt -check .
packer validate .
packer build -on-error=ask .      # leaves the machine up to inspect
```

On a VM made from a Windows image:

```
Get-ChildItem C:\Windows\Panther -Filter '*unattend*.xml'   # nothing
winrm get winrm/config/service                               # AllowUnencrypted = false
Get-NetFirewallRule -Name PackerWinRM                        # not found
```

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it causes on a clone>
Fix: <the change, one line>
```

For anything left in the image, say what it leaks or breaks when the image is used twice. If it is clean, say so in a sentence.
