# Hyper-V with the `taliesins/hyperv` provider

The provider runs PowerShell on the Hyper-V host over WinRM. Everything it does, it does
with the Hyper-V module on the host, and what that module cannot express through the
provider's schema is left to PowerShell (see the end of this file).

Checked against provider 1.2.1. Before using an attribute not shown here, check the
provider docs for the pinned version; the schema is large and not every `Set-VM*`
parameter is in it.

## Provider setup

```hcl
terraform {
  required_version = ">= 1.4.0" # terraform_data; an ephemeral variable needs 1.10 (OpenTofu 1.11)
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "= 1.2.1"
    }
  }
}

# Host, port, and credentials come from HYPERV_HOST, HYPERV_USER, HYPERV_PASSWORD, and
# the other HYPERV_* variables, which CI sets from masked variables.
provider "hyperv" {}
```

Every provider argument has a `HYPERV_*` environment variable. Set them in CI; write
none in the code:

| Variable | What | Default |
|---|---|---|
| `HYPERV_HOST` | the Hyper-V host name | `127.0.0.1` |
| `HYPERV_PORT` | WinRM port | `5986` |
| `HYPERV_HTTPS` | WinRM over HTTPS | `true` |
| `HYPERV_INSECURE` | skip TLS verification | `false` — keep it |
| `HYPERV_USE_NTLM` | NTLM instead of basic | `true` |
| `HYPERV_USER`, `HYPERV_PASSWORD` | the account that runs the scripts | `Administrator` |
| `HYPERV_KERBEROS_REALM`, `HYPERV_KERBEROS_SERVICE_PRINCIPAL_NAME`, `KRB5_CONFIG`, `KRB5CCNAME` | Kerberos instead of NTLM | — |
| `HYPERV_CACERT_PATH` | CA that signed the host's WinRM certificate | — |
| `HYPERV_SCRIPT_PATH` | read, but not used by the 1.2.1 script runner | `C:/Temp/terraform_%RAND%.cmd` |
| `HYPERV_TIMEOUT` | connection timeout | `30s` |

- HTTPS on 5986 with a certificate the runner trusts (`HYPERV_CACERT_PATH`). Never
  `HYPERV_INSECURE=true` outside a lab, and never WinRM over plain HTTP.
- Kerberos in a domain (set `HYPERV_USE_NTLM=false` and the Kerberos variables, with a
  `krb5.conf` in the runner image). NTLM over HTTPS is acceptable in a lab.
- A dedicated service account, not a domain admin. The provider runs every script as a
  scheduled task registered with the account's name and password, so the account
  likely needs all of these. They come from reading the provider's source; write down
  what the account really needed once you have tried it on the host:
  - the host's `Hyper-V Administrators` group, for the Hyper-V cmdlets;
  - remote access over WinRM (the host's `Remote Management Users` group);
  - the right to log on as a batch job, for the scheduled task. The task needs the
    password, so set `HYPERV_PASSWORD` even with Kerberos and a ticket cache;
  - write access to the folders that hold images, VM disks, and seeds.
- Scripts are uploaded to the account's `%TEMP%` on the host and deleted after a
  successful call. When a call fails, the wrapper that holds the account's password in
  clear text stays there. Keep that profile readable by the account and administrators
  only, and clean `%TEMP%` after a failed apply.
- One provider block reaches one host, and a module's provider cannot change per
  `for_each` key. VMs on a second host are a second `module` block (`module "vm_hv02"`
  with its own map) that gets `providers = { hyperv = hyperv.hv02 }`.
- Every alias reads the same `HYPERV_*` variables, so the aliased block has to set
  `host` as an argument, from a variable, and its user and password too if they differ
  (the password from an `ephemeral` variable). It is the one exception to "no provider
  arguments" in the SKILL.

## A VM from the golden image

Packer writes images to an image store on the host (for example `D:\Images`), named with
the date and git sha, and never overwrites one. Terraform makes each VM's OS disk from
an image in one of two ways.

### Copy (`source`): the default

```hcl
resource "hyperv_vhd" "os" {
  path   = "${var.vm_root}\\${var.name}\\${var.name}-os.vhdx"
  source = "${var.image_store}\\${var.image}"
  size   = var.os_disk_gb * 1024 * 1024 * 1024 # grows the copy; the guest extends its partition

  lifecycle {
    replace_triggered_by = [terraform_data.image] # see "Which image a VM uses"
  }
}
```

- Takes minutes (a full copy), then the VM owns its disk outright.
- Use for production and anything long-lived: it can be moved, migrated, backed up, and
  outlive the image.
- `size` must be a multiple of 4096 and can only grow the disk. The guest has to extend
  the partition: cloud-init's `growpart` does it on Linux; on Windows, a first-boot
  command or Ansible extends `C:`.

### Differencing (`parent_path`)

```hcl
resource "hyperv_vhd" "os" {
  path        = "${var.vm_root}\\${var.name}\\${var.name}-os.vhdx"
  vhd_type    = "Differencing" # the default, Dynamic, fails without a size
  parent_path = "${var.image_store}\\${var.image}"

  lifecycle {
    replace_triggered_by = [terraform_data.image] # see "Which image a VM uses"
  }
}
```

- Created in seconds and stores only the blocks the VM changes.
- The VM depends on the parent for as long as it exists. If the parent changes, every
  child is corrupt; if it moves or is deleted, every child stops booting. Make image
  files read-only and keep each version until no VM uses it.
- Reads that miss the child go to the parent, so many children on one parent share its
  disk's speed.
- Use for short-lived VMs: test environments, CI targets, a lab. Not for production.
- `parent_path` excludes `size`, so the disk is as large as the image.
- Set `vhd_type = "Differencing"`. The provider docs say the type is ignored with
  `parent_path`, but the create script makes a dynamic disk unless the type says
  otherwise, and stops with `Vhd Size must be specified`.

### Which image a VM uses

Put the image in each VM's entry of the map (see `vms` in the SKILL), not in one global
variable, so a new image reaches VMs one at a time, when you choose, not every VM in one
apply.

A new image must replace the OS disk, the seed ISO, and the VM together, and the
provider will not do that on its own. `source` and `parent_path` do not force a new
disk: a changed image plans as `~ update in-place`, the apply succeeds, the state records
the new image, and the disk on the host still holds the old one. Make the replacement
explicit with one `terraform_data` (Terraform 1.4+) that holds the image:

```hcl
resource "terraform_data" "image" {
  input = var.image
}
```

`hyperv_vhd.os`, `hyperv_iso_image.seed`, and `hyperv_machine_instance.this` each have
`lifecycle { replace_triggered_by = [terraform_data.image] }`, as in the snippets here.
An image change must plan as `must be replaced` for all three. An `update in-place` on
the disk means a trigger is missing: stop and add it. Try one image change on a host
before you rely on it.

Keep data off the OS disk. The OS disk is rebuilt from the image; a disk that holds state
is a separate `hyperv_vhd` (with `size` and `vhd_type = "Dynamic"`, no `source`) and has
`lifecycle { prevent_destroy = true }`. Name it `<name>-data.vhdx` in the VM's folder;
the rough edge on deleting a disk says why the name matters.

## The machine

```hcl
resource "hyperv_machine_instance" "this" {
  name                   = var.name
  path                   = var.vm_root # Hyper-V adds <name>\, so the config sits next to the disks
  generation             = 2
  processor_count        = var.cpus
  static_memory          = true
  memory_startup_bytes   = var.memory_gb * 1024 * 1024 * 1024
  checkpoint_type        = "Disabled"
  automatic_start_action = "StartIfRunning"
  automatic_stop_action  = "ShutDown"
  state                  = "Running"
  notes                  = "Managed by Terraform."

  vm_firmware {
    enable_secure_boot   = "On"
    secure_boot_template = var.os == "windows" ? "MicrosoftWindows" : "MicrosoftUEFICertificateAuthority"
    boot_order {
      boot_type           = "HardDiskDrive"
      controller_number   = 0
      controller_location = 0
    }
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.os.path
  }

  dvd_drives {
    controller_number   = 0
    controller_location = 1
    path                = hyperv_iso_image.seed.resolve_destination_iso_file_path
  }

  network_adaptors {
    name                = "lan"
    switch_name         = data.hyperv_network_switch.this.name
    vlan_access         = var.vlan_id != null
    vlan_id             = var.vlan_id
    dynamic_mac_address = var.mac == null
    static_mac_address  = var.mac
    wait_for_ips        = true
  }

  integration_services = {
    "Guest Service Interface" = false
    "Heartbeat"               = true
    "Key-Value Pair Exchange" = true
    "Shutdown"                = true
    "Time Synchronization"    = true
    "VSS"                     = true
  }

  lifecycle {
    replace_triggered_by = [terraform_data.image] # see "Which image a VM uses"
  }
}
```

- **`path`** keeps the VM's configuration files under `vm_root` with its disks, instead
  of the host's default folder. Set it from the start: a change replaces the VM.
- **Generation 2** always: UEFI, secure boot, SCSI boot disk. Generation 1 only for an
  OS that cannot boot UEFI.
- **Secure boot template**: `MicrosoftWindows` for Windows, `MicrosoftUEFICertificateAuthority`
  for Linux. The wrong one leaves the VM at a firmware screen saying no boot device.
- **Boot order** written out, with the disk first. Otherwise a generation 2 VM may try
  the network first and wait for PXE.
- **Checkpoints off.** On a server they grow AVHDX chains that nobody merges, and a
  restore rolls the machine back behind what Ansible and the state believe it is.
  Backups are the host's job, not checkpoints.
- **Static memory** for servers that size their caches at start (SQL Server, IIS app
  pools, the .NET GC). Dynamic memory (`dynamic_memory = true` with minimum and maximum)
  for light utility VMs only.
- **Switches and VLANs.** The virtual switch belongs to the host and is created once, not
  by each environment. Look it up with `data "hyperv_network_switch"` and a
  postcondition (see the end of this file) so a typo fails the plan. `vlan_access` and
  `vlan_id` give an access port; the provider has no trunk mode.
- **Static MAC** only when a DHCP reservation or a licence is tied to it. Write it as 12
  hex digits and take it from a locally administered range (first byte `02`), so it
  cannot collide with the host's dynamic pool (`00155D…`). Validate it in the variable:
  `can(regex("^02[0-9A-F]{10}$", var.mac))`.
- **`wait_for_ips`** makes the apply wait until the guest reports an address through the
  Key-Value Pair Exchange service. Linux guests need the Hyper-V daemons for that
  (`hyperv-daemons` on Debian and RHEL, `linux-cloud-tools-virtual` on Ubuntu), or the
  apply waits until `wait_for_ips_timeout`. If the address is known in advance (a
  reservation, a static IP in the seed), set `wait_for_ips = false` and use the known name.
- **Nested virtualization** is in the schema: `vm_processor { expose_virtualization_extensions = true }`.
  It needs dynamic memory off.

The guest's addresses are on the adaptor; keep the IPv4 ones:

```hcl
output "ipv4" {
  value = [
    for ip in hyperv_machine_instance.this.network_adaptors[0].ip_addresses : ip
    if can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", ip))
  ]
}
```

## First boot: the seed ISO

Hyper-V has no metadata service. Per-VM settings (hostname, network, the first account)
reach the guest on a small ISO in the VM's DVD drive, built by `hyperv_iso_image` from a
zip that the `archive_file` data source makes from strings, so no temporary files exist.

```hcl
locals {
  seed_files = var.os == "windows" ? {
    "Autounattend.xml" = templatefile("${path.module}/templates/Autounattend.xml.tftpl", {
      computer_name = upper(var.name)
      time_zone     = var.time_zone
    })
    } : {
    "meta-data" = yamlencode({ "instance-id" = "${var.name}-${var.image}", "local-hostname" = var.name })
    "user-data" = "#cloud-config\n${yamlencode(local.cloud_config)}"
  }
}

data "archive_file" "seed" {
  type        = "zip"
  output_path = "${path.root}/.seed/${var.name}.zip"

  dynamic "source" {
    for_each = local.seed_files
    content {
      filename = source.key
      content  = source.value
    }
  }
}

resource "hyperv_iso_image" "seed" {
  volume_name               = var.os == "windows" ? "UNATTEND" : "CIDATA" # upper case only
  source_zip_file_path      = data.archive_file.seed.output_path
  source_zip_file_path_hash = data.archive_file.seed.output_sha
  destination_iso_file_path = "${var.vm_root}\\${var.name}\\seed.iso"
  iso_media_type            = "dvdplusrw_duallayer"
  iso_file_system_type      = "iso9660|joliet"

  lifecycle {
    replace_triggered_by = [terraform_data.image] # see "Which image a VM uses"
    # Read once at first boot; a rebuild under a running VM changes nothing in the guest.
    ignore_changes = [source_zip_file_path_hash]
  }
}
```

- **Linux: cloud-init NoCloud.** The volume label `CIDATA` (the provider allows only
  upper case; cloud-init accepts `cidata` or `CIDATA`) with `meta-data` and `user-data`
  at the root. Add a `network-config` entry for a static address; without it the guest
  uses DHCP. cloud-init runs again whenever `instance-id` changes, so derive it from the
  VM and its image, never from a timestamp. An image change replaces the disk and the
  seed together, so a new `instance-id` always meets a new disk.
- **Windows: `Autounattend.xml`.** After sysprep, Windows Setup reads an answer file named
  `Autounattend.xml` from the root of removable media in the `specialize` and
  `oobeSystem` passes: computer name, time zone, the WinRM listener, an offline domain
  join. The Windows branch puts that one file on the seed instead; the label does not
  matter. Setup looks in `%WINDIR%\Panther` before removable media, so the image must
  not carry its own answer file there, or the ISO is ignored. If the image has
  Cloudbase-Init, it can read the same `CIDATA` ISO as Linux instead.
- **The seed is read once, at first boot.** It is built from module-wide `locals`, so
  one edit to the cloud-config or the answer file changes the seed of every VM. Without
  `ignore_changes`, the provider deletes and rebuilds the ISO of every running VM: that
  changes nothing in the guest, and the delete will probably fail while the ISO sits in
  the DVD drive. With it, a seed edit reaches new VMs and VMs whose image changes;
  running VMs keep the seed they booted from, and Ansible owns everything after first
  boot. Neither case has been tried on a host yet.
- `archive_file` writes the zip at plan time. In CI the apply job needs it too, so pass
  `.seed/` from the plan job to the apply job as an artifact with `plan.cache`. Plan
  twice in a row once: the second plan must show no change to the ISO.
- **Secrets on the ISO are clear text**: in the ISO on the host, in the zip the provider
  uploads to the account's `%TEMP%` and keeps there while the ISO exists, in the
  `.seed/` CI artifact, and in the state. Put only what is safe there: an SSH public
  key, a password hash, a local admin password that Ansible changes on its first run,
  or an offline domain-join blob from `djoin /provision` (it joins only that one
  computer). Never a reusable domain or service password.
- `archive_file` comes from `hashicorp/archive`. Pin it like any provider, and add the
  `.seed/` folder to `.gitignore`.

## What the provider cannot do

Hand these to PowerShell on the host, run as its own pipeline step after apply, never from
`local-exec`:

- Virtual TPM and key protector (`Set-VMKeyProtector`, `Enable-VMTPM`), needed for
  BitLocker in the guest.
- Trunk-mode VLANs (`Set-VMNetworkAdapterVlan -Trunk`).
- Failover cluster roles (`Add-ClusterVirtualMachineRole`), Hyper-V Replica, live and
  storage migration.
- Copying files into a running guest (`Copy-VMFile`).
- Host configuration: the host's own network, storage, and Hyper-V settings.

If such a step changes something the provider also manages (memory, processor, adaptors),
the next plan shows it as drift and reverts it. Keep the two sets of settings separate.

## Known rough edges

- Argument values are the PowerShell enum names and are case sensitive in places
  (`"On"`, `"Off"`, `"Scsi"`, `"Running"`). Copy them from the docs.
- Paths on the host are Windows paths in HCL strings: escape the backslash (`"D:\\VMs"`)
  and always give absolute paths.
- **Any in-place change to `hyperv_machine_instance` restarts the VM.** Before
  applying a change to memory, processors, firmware, notes, integration services,
  adaptors, DVD or disk drives, the provider shuts a running VM down
  (`Stop-VM -Force`) and starts it again. A plan that shows `~ update in-place` on a
  production VM is a reboot: apply it in a maintenance window, one VM at a time.
- **Destroying a disk deletes every file in its folder whose name starts with the
  disk's name.** The provider's delete removes `web01*` when it destroys `web01.vhdx`,
  so `web01-data.vhdx` goes with it, and `web1.vhdx` takes `web10.vhdx`.
  `prevent_destroy` on the other disk does not help: Terraform never planned to touch
  it. Give each VM its own folder, and never let one disk's base name be the start of
  another's in that folder. The layout here (`<name>\<name>-os.vhdx` and
  `<name>\<name>-data.vhdx`) is safe for that reason.
- **`hyperv_vhd` does not replace a disk when its image changes.** It reports an
  in-place update and leaves the old disk. See "Which image a VM uses".
- The provider is maintained by a small team; pin it exactly and read the changelog
  before raising the pin.
- `terraform validate` cannot catch a wrong path on the host, a missing switch, or a
  missing image. Look them up so the plan fails instead of the apply. Neither lookup
  fails on its own, so each needs a postcondition.

  The `hyperv_vhd` data source does not fail on a missing file, and in 1.2.1 its
  `exists` is the wrong way round (`true` when the file is missing). Test `path`
  instead: the read copies the path the host reports and leaves it empty when there is
  no file.

  ```hcl
  data "hyperv_vhd" "image" {
    path = "${var.image_store}\\${var.image}"
    lifecycle {
      postcondition {
        # Not self.exists: it is inverted in provider 1.2.1.
        condition     = self.path != ""
        error_message = "Image ${var.image} is not in ${var.image_store} on the host."
      }
    }
  }
  ```

  The `hyperv_network_switch` data source returns without an error when the switch is
  not there, and hands back the name from the config; the apply then fails when it
  attaches the adaptor. It sets the id only when it finds the switch, and the name
  comparison is case sensitive (`lan` does not find `LAN`).

  ```hcl
  data "hyperv_network_switch" "this" {
    name = var.switch_name
    lifecycle {
      postcondition {
        condition     = self.id == var.switch_name
        error_message = "Switch ${var.switch_name} is not on the host. The name is case sensitive."
      }
    }
  }
  ```
