---
name: packer
description: Use when writing or changing Packer templates that build golden images — HCL2 sources and builds, required_plugins, variables, the hyperv-iso builder, a Windows answer file and sysprep, Ubuntu autoinstall or Debian preseed, cloud-init clean up, provisioners, image names, or the Packer build job in GitLab CI (e.g. "write a packer template for Windows Server 2025 on Hyper-V", "build a golden image", "add Windows Update to the image", "why does packer wait for SSH forever", "sysprep the image"). For reviewing a Packer template, use the packer-reviewer agent instead.
---

# Packer

An image is copied into every VM, so whatever is wrong in it is wrong everywhere. Write
the template so a build can be repeated (pinned plugins, pinned ISO, a new name for every
image) and the image is clean: no build password, no build answer file, no machine
identity, and ready for the first boot that Terraform's seed ISO drives.

The VMs are made from the image with Terraform (`terraform/references/hyperv.md`, D18).
For a review of finished templates, run the `packer-reviewer` agent (in Codex, the
`packer-review` skill). For the PowerShell scripts the build runs, `powershell`. For
comments, `code-comments`.

## 0. Check what is installed

Run `packer version` and read the `packer` block of the template. Packer 1.10 and later
ship no plugins: everything except the built-in provisioners (`file`, `shell`,
`shell-local`, `powershell`, `windows-shell`, `windows-restart`, `breakpoint`) and
post-processors (`manifest`, `checksum`, `compress`, `shell-local`, `artifice`) comes
from `required_plugins` through `packer init`.

HCL2 only. A JSON template is converted once with `packer hcl2_upgrade` and then edited as
HCL.

## 1. Layout: one folder per image

```
images/
  windows-2025/
    windows-2025.pkr.hcl       # packer block, source, build
    variables.pkr.hcl
    files/Autounattend.xml.pkrtpl   # build-only answer file, filled in at build time
    scripts/*.ps1
  ubuntu-2404/
    ubuntu-2404.pkr.hcl
    variables.pkr.hcl
    files/user-data.pkrtpl
    scripts/*.sh
```

- `packer build images/windows-2025` builds one image. Packer reads every `*.pkr.hcl`
  in the folder, so nothing else lives there.
- What differs per site (the switch, the image store) is a variable set by the CI
  template, never written into the template.
- Non-secret values a person would change (the ISO, sizes) go in a committed
  `*.auto.pkrvars.hcl` next to the template.
- `.gitignore` covers what a build writes: `output/`, `packer_cache/`, and
  `packer-manifest.json`.

## 2. Plugins

```hcl
packer {
  required_version = ">= 1.11.0"
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "= 1.1.5"
    }
    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = "= 0.18.5"
    }
  }
}
```

- Pin each plugin exactly. Packer has no lock file, so the pin is the only record of what
  was tested.
- `packer init <folder>` downloads them. CI runs it in every job, so a pin change goes
  through a commit.
- `packer init` asks the GitHub API for releases. In CI, set `PACKER_GITHUB_API_TOKEN`,
  or a busy runner hits the anonymous rate limit.

## 3. Variables, secrets, and the image name

```hcl
variable "build_password" {
  type        = string
  sensitive   = true
  description = "Password of the build account, used only during the build. Set PKR_VAR_build_password from a masked CI variable."
}

variable "git_sha" {
  type        = string
  description = "Short commit sha of this build. CI sets PKR_VAR_git_sha from CI_COMMIT_SHORT_SHA."
  validation {
    condition     = can(regex("^[0-9a-f]{7,12}$", var.git_sha))
    error_message = "git_sha must be a short commit sha."
  }
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of the install ISO, for example sha256:..."
  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.iso_checksum))
    error_message = "iso_checksum must be sha256:<64 hex digits>, never none."
  }
}

locals {
  # win2025-20261115-a1b2c3d: the file name Terraform's vms map points at.
  image_name = "win2025-${formatdate("YYYYMMDD", timestamp())}-${var.git_sha}"
}
```

- Secrets come from `PKR_VAR_<name>` environment variables set by masked CI variables,
  never from a committed `.pkrvars.hcl` and never from a default.
- `sensitive = true` keeps the value out of Packer's output. It still reaches the VM in
  clear text, so the build account is for the build only (section 5) and its password
  is not used for anything else.
- Every image gets a new name from the date and the commit. Nothing is ever overwritten:
  a VM made from an image, and every differencing disk on it, needs that file unchanged.

## 4. The `hyperv-iso` source

```hcl
source "hyperv-iso" "win2025" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vm_name              = local.image_name
  generation           = 2
  enable_secure_boot   = true
  secure_boot_template = "MicrosoftWindows" # Linux: MicrosoftUEFICertificateAuthority
  cpus                 = 4
  memory               = 8192  # MB
  disk_size            = 61440 # MB; Terraform can grow the copy, never shrink it
  switch_name          = var.switch_name
  headless             = true

  skip_export      = true # only the VHDX is needed; Terraform makes the VMs
  output_directory = "output/${local.image_name}"
}
```

- **Packer runs on the Hyper-V host.** The builder drives the Hyper-V PowerShell module
  on the machine it runs on; there is no remote mode. That is why the build job has the
  `hyperv` runner tag. The runner's account must be in the host's Hyper-V
  Administrators group.
- **The same generation and secure boot template as the VMs.** Terraform makes
  generation 2 VMs; a generation 1 image does not boot in them.
- **The switch** must give the VM an address by DHCP, and the runner must reach that
  address (WinRM on 5985, SSH on 22). Packer learns the address from Hyper-V's
  integration services, so the guest must report it: Windows does; Linux needs the
  Hyper-V daemons in the installed system (section 6).
- **Keep `disk_size` small.** A copied OS disk can be grown by Terraform's `os_disk_gb`
  and extended in the guest; a differencing disk is exactly as big as its image.
- **`skip_export = true`** leaves the disk at
  `<output_directory>/Virtual Hard Disks/<vm_name>.vhdx`, compacted. The exported VM
  configuration would only be thrown away.
- **`cd_files` and `cd_content`** put files on an extra ISO (generation 2 has no
  floppy). Packer makes the ISO with `oscdimg` (Windows ADK, Deployment Tools) or
  `xorriso`, which must be on the host's `PATH`, or the build stops at that step.
- **`boot_command` is the fragile part.** It types keys at the firmware or boot loader,
  and its timing differs between hosts. Keep it as short as the media allows and let an
  answer file or autoinstall do the rest.
- Settings a VM needs at run time (nested virtualization, a TPM) are set on each VM by
  Terraform or by PowerShell after the apply. The image does not carry them; turn them on
  in the build only if the install itself needs them.

## 5. A Windows image

### The build answer file

Windows Setup reads `Autounattend.xml` from the root of any removable media. Fill it in
at build time with `cd_content`, so the password is never committed:

```hcl
cd_content = {
  "Autounattend.xml" = templatefile("files/Autounattend.xml.pkrtpl", {
    edition  = var.image_edition
    password = var.build_password
  })
}
cd_label = "PACKER"
```

Two path rules that differ: `templatefile` reads its path from the template's folder,
while provisioner `script` and `scripts` paths are read from the folder Packer runs in, so
write those as `"${path.root}/scripts/…"`. `packer validate` catches a wrong script path;
check a wrong `templatefile` path the same way, from the folder CI runs in.

The password is written into XML, so give the variable a `validation` that rejects `<`,
`>`, and `&`.

It does four things and nothing more: partitions the disk for UEFI (EFI, MSR, Windows),
picks the edition by its `/IMAGE/NAME`, sets the Administrator password, and logs on once
to open WinRM for the build:

```
Enable-PSRemoting -SkipNetworkProfileCheck -Force
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
New-NetFirewallRule -Name PackerWinRM -DisplayName 'Packer build WinRM' -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any
```

- Those three settings are for the build only, on the build switch only. The shutdown
  command undoes them (below).
- Connect with NTLM (`winrm_use_ntlm = true`), so Basic authentication stays off.
- The product key: evaluation media needs none; volume media needs the KMS client key
  from Microsoft's "KMS client activation and product keys" page. A real key is a
  secret.

### Communicator and provisioners

```hcl
communicator   = "winrm"
winrm_username = "Administrator"
winrm_password = var.build_password
winrm_use_ntlm = true
winrm_timeout  = "2h" # Setup and the first logon
```

```hcl
build {
  sources = ["source.hyperv-iso.win2025"]

  provisioner "powershell" {
    scripts = ["${path.root}/scripts/baseline.ps1"]
  }

  provisioner "windows-update" {
    filters = ["exclude:$_.Title -like '*Preview*'", "include:$true"]
  }

  provisioner "powershell" {
    scripts = ["${path.root}/scripts/cleanup.ps1"] # update downloads, component store
  }

  provisioner "windows-restart" {} # sysprep refuses to run with a reboot pending

  provisioner "powershell" {
    scripts = ["${path.root}/scripts/sysprep.ps1"] # always the last provisioner
  }
}
```

- Provisioner scripts run in Windows PowerShell 5.1, the only PowerShell a fresh Windows
  has. Start each with `Set-StrictMode -Version Latest` and
  `$ErrorActionPreference = 'Stop'`, so the first failure fails the build. Packer
  fails the build when a script's exit code is not 0.
- Some calls refuse a network logon, which is what WinRM gives. If a script fails with
  access denied as Administrator, run that provisioner with `elevated_user` and
  `elevated_password` (a scheduled task as that user).
- `windows-update` reboots as often as it needs. The `windows-restart` before sysprep
  finishes what the last update and the component clean up left pending.
- Install only what every VM needs: roles and features, agents, hardening. Anything that
  differs per host or per app (IIS sites, app pools, certificates) is Ansible's job after
  first boot (D18).

### Sysprep, and the answer file it must leave behind

The clone's first boot is driven by the seed ISO Terraform attaches, which holds its own
`Autounattend.xml` (computer name, time zone). Windows Setup looks in
`C:\Windows\Panther` before removable media, and Setup has already copied the build's
answer file there during the install. If that copy is still in the image, every clone
ignores the seed. So the last provisioner:

1. removes `unattend.xml` and `autounattend.xml` from `C:\Windows\Panther`;
2. runs `sysprep.exe /generalize /oobe /quiet /quit /mode:vm` (`/mode:vm` because the
   image only ever boots as a Hyper-V generation 2 VM), and never `/unattend:`, which
   caches another answer file in Panther. Start it with `Start-Process -Wait`:
   `sysprep.exe` is a GUI program, and PowerShell does not wait for one called with `&`;
3. waits until `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State` shows
   `IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE`, and on a timeout throws with the end of
   `C:\Windows\System32\Sysprep\Panther\setuperr.log`, so a failed sysprep fails the
   build instead of leaving a VM that never shuts down;
4. removes the Panther answer files again.

Sysprep in a provisioner, not in `shutdown_command`: a provisioner's failure is visible,
and the shutdown command can then undo the build's WinRM settings, which a provisioner
cannot do without cutting its own connection.

```hcl
shutdown_command = join(" && ", [
  # Schedule the shutdown first: the WinRM changes after it may end this session.
  "shutdown /s /t 10 /f /d p:4:1 /c Packer",
  "powershell -NoProfile -Command \"Remove-NetFirewallRule -Name PackerWinRM; Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $false\"",
])
shutdown_timeout = "15m"
```

Packer sends the shutdown command and then only waits for the VM to stop, so a session
that ends early is fine. Windows Server's own WinRM listener (HTTP with Kerberos, which
encrypts) stays, which is what Ansible uses after the domain join (D24).

The Administrator password stays as the build set it until the clone's first boot sets a
new one, which is why the build password is used for nothing else.

## 6. A Linux image

### Ubuntu autoinstall from the extra ISO

```hcl
cd_content = {
  "meta-data" = ""
  "user-data" = templatefile("${path.root}/files/user-data.pkrtpl", {
    password_hash = bcrypt(var.build_password)
  })
}
cd_label = "cidata"

boot_wait    = "5s"
boot_command = ["e<wait><down><down><down><end> autoinstall<f10>"]
```

- The ISO with the label `cidata` is found by the installer's cloud-init. It is used
  instead of Packer's HTTP server, because the host's firewall blocks the VM from
  reaching that server unless someone opens a port.
- The boot command adds `autoinstall` to the GRUB entry; without it the installer asks
  for confirmation. Check the line count against the ISO's `boot/grub/grub.cfg`.
- `user-data` creates the build user with `password_hash` (`bcrypt()` makes a `$2a$`
  hash, which the installed system accepts), gives it password-less sudo for the build
  in `late-commands` (`/target/etc/sudoers.d/packer`), installs the OpenSSH server, and
  lists in
  `packages:` the Hyper-V daemons: `linux-cloud-tools-virtual` on Ubuntu,
  `hyperv-daemons` on Debian and RHEL. They must be there on the first boot of the
  installed system, not added by a provisioner: without them the guest never reports its
  address, Packer waits for SSH until it times out, and so does Terraform's
  `wait_for_ips` on every clone.
- Debian uses a preseed file instead (`auto url=…` or `file=/cdrom/…` on the kernel
  line); RHEL a kickstart (`inst.ks=`). The rules are the same.

```hcl
communicator = "ssh"
ssh_username = "packer"
ssh_password = var.build_password
ssh_timeout  = "1h"

# Lock the build account last: sudo has already read sudoers when the file goes.
shutdown_command = "sudo sh -c 'rm -f /etc/sudoers.d/packer; usermod --lock --expiredate 1 packer; shutdown -P now'"
```

### Provisioners

- `shell` with `execute_command = "chmod +x {{ .Path }}; sudo {{ .Vars }} {{ .Path }}"`,
  and scripts that start with `#!/bin/bash` and `set -euo pipefail`, so the first
  failure fails the build.
- The `ansible` provisioner runs Ansible on the machine running Packer, and that is the
  Windows Hyper-V host, where Ansible does not run. Use `ansible-local` (same
  `github.com/hashicorp/ansible` plugin), which runs the playbook inside the guest, and
  remove Ansible in the clean up. Or keep the image to shell scripts and leave the roles
  to the Ansible run after first boot.

### Clean up for the first boot

The last provisioner, as root:

```bash
set -euo pipefail
cloud-init clean --logs --seed
# The installer's leftovers stop cloud-init from configuring the clone's network.
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml
truncate -s 0 /etc/machine-id                 # emptied, not deleted
rm -f /etc/ssh/ssh_host_*                     # each clone makes its own
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf   # the build's password login
apt-get clean && rm -rf /var/lib/apt/lists/*
```

cloud-init stays installed and enabled: on the clone it reads the `CIDATA` seed and sets
the hostname, the users, and the network. Check the file names against the release: the
installer's netplan file changed name between Ubuntu releases. The shutdown command
locks the build account.

## 7. Output: the image store

```hcl
post-processor "shell-local" {
  execute_command    = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "{{.Script}}"]
  tempfile_extension = ".ps1"
  inline = [
    "$ErrorActionPreference = 'Stop'",
    "$target = Join-Path '${var.image_store}' '${local.image_name}.vhdx'",
    "if (Test-Path $target) { throw \"$target exists; an image is never overwritten\" }",
    "Copy-Item 'output/${local.image_name}/Virtual Hard Disks/${local.image_name}.vhdx' $target",
    "Set-ItemProperty $target -Name IsReadOnly -Value $true",
  ]
}

post-processor "manifest" {
  output      = "packer-manifest.json"
  custom_data = { image = "${local.image_name}.vhdx", git_sha = var.git_sha }
}
```

- The image store is the folder Terraform's `image_store` points at (`D:\Images`).
- Read-only, because a differencing disk is corrupt the moment its parent changes.
- Delete an old image only when no VM's `image` names it any more.
- Keep `packer-manifest.json` as the job artifact: it says which commit made which file.

## 8. The pipeline

The jobs live in the `ci-templates` repo (D21):

```yaml
packer-validate:
  stage: test
  tags: [docker]
  image:
    name: hashicorp/packer:1.16.2
    entrypoint: [""] # the image's entrypoint is packer itself
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - packer init images/windows-2025
    - packer fmt -check -recursive images
    # The real password is a protected variable, which a merge request does not get.
    - packer validate -var git_sha=$CI_COMMIT_SHORT_SHA -var build_password=unused images/windows-2025

packer-build:
  stage: build
  tags: [hyperv]
  resource_group: hyperv-image-build # two builds on one host compete for memory
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      changes: [images/windows-2025/**/*]
  variables:
    PKR_VAR_git_sha: $CI_COMMIT_SHORT_SHA
  script:
    - packer init images/windows-2025
    - packer build -color=false images/windows-2025
  artifacts:
    paths: [packer-manifest.json]
    expire_in: 90 days
```

- `PKR_VAR_build_password` is a masked, protected project variable, so only protected
  branches build.
- A monthly scheduled pipeline rebuilds every image with the month's updates. Each build
  is a new file; VMs move to it one at a time when their `image` changes in Terraform.
- Never `-on-error=abort` in CI: it leaves the build VM and its disk on the host.
  `-on-error=ask` is for a person at the host debugging one build.
- The `hyperv` runner is a Windows shell runner, so a script line that needs a variable
  uses PowerShell syntax (`$env:CI_COMMIT_SHORT_SHA`).

## 9. Style

- `packer fmt` decides formatting.
- One `source` and one `build` per image folder. Two images that share most settings are
  still two folders; the shared values are variables set by CI.
- Long logic goes in a script file under `scripts/`, not in an `inline` list.
- Comment the why (a Setup quirk, a host limit), never what a block obviously does.

## Before calling it done

```
packer init images/<image>
packer fmt -check -recursive images
packer validate images/<image>
packer build images/<image>          # on the Hyper-V host
```

Then make one VM from the image with Terraform and check its first boot: it took the
seed's computer name (Windows) or hostname (Linux), so the seed was read;
`C:\Windows\Panther` has no answer file; `winrm get winrm/config/service` shows
`AllowUnencrypted = false` and the `PackerWinRM` firewall rule is gone; on Linux,
`cloud-init status --long` is `done`, the machine id and SSH host keys are new, and
`packer` cannot log in. Then run the `packer-reviewer` agent on the template.
