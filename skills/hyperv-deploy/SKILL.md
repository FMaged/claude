---
name: hyperv-deploy
description: Use when creating, changing, or removing Hyper-V VMs with PowerShell instead of Terraform — a deploy script with one data file per environment, VMs from the Packer golden image (a copy or a differencing disk), first-boot files for Windows and cloud-init, switch and VLAN, the virtual TPM, -WhatIf as the plan, safe re-runs, and one owner per VM (e.g. "deploy a VM on Hyper-V with powershell", "create these lab VMs without terraform", "a script that makes VMs from our golden image", "remove this lab VM", "should this VM be terraform or a script?"). For VMs managed with Terraform, use terraform instead.
---

# Hyper-V VMs with PowerShell

A deploy script has no plan file and no state, so it has to give itself both. It reads the
host, shows under `-WhatIf` exactly what it would change, changes only the difference,
and does nothing on a second run. It also refuses every VM it did not make, because two
owners of one VM undo each other's changes.

This is the PowerShell path of D18; `terraform` with `references/hyperv.md` is the other,
and the image comes from `packer`. For PowerShell in general (strict mode,
`ShouldProcess`, credentials, Pester), `powershell`; for a review of a finished deploy
script, `powershell-review`. The worked example is `evals/examples/hyperv-deploy/` in
the skills repo.

## 0. Terraform or a script

| Terraform | This script |
|---|---|
| VMs that live long and change: staging, production | A lab, a test environment you throw away, a one-off VM |
| VMs the pipeline deploys, with a plan in the merge request | A host the pipeline cannot reach, or a VM that must exist before the pipeline does (the runner, a domain controller) |
| Several people change them | One person runs it, on the host |

A VM has one owner. The script writes `Managed-by: hyperv-deploy` in the VM's notes and
refuses any VM whose notes do not say so, which covers VMs from Terraform and VMs made by
hand. To move a VM to the other tool, do it by hand: take it over there, then change its
notes. Never run both against it.

## 1. Layout

```
hyperv/
  Deploy-HyperVVM.ps1          creates and changes VMs
  Remove-HyperVVM.ps1          deletes a VM and its own folder
  HyperVDeploy.psm1 / .psd1    config checks, drift, first-boot files; changes nothing
  HyperVDeploy.Tests.ps1
  envs/
    lab.psd1                   one data file per environment
```

- Logic that only reads and decides (checking the data file, comparing a VM with it,
  building first-boot files) lives in the module, where tests call it directly.
  Everything that changes the host lives in the two scripts, inside `ShouldProcess`.
- The scripts run on the Hyper-V host: mounting a VHDX to write first-boot files works
  only there. In CI that is the `hyperv` runner tag. The Hyper-V cmdlets have
  `-ComputerName`, but `Mount-VHD` and file writes do not reach across, so from another
  machine open a session on the host and run a copy of the folder there.

## 2. The data file

```powershell
@{
    VmRoot     = 'D:\VMs'
    ImageStore = 'D:\Images'
    SwitchName = 'LAN'
    TimeZone   = 'W. Europe Standard Time'
    Vms        = @{
        'lab-web01' = @{
            Image    = 'win2025-20261115-a1b2c3d.vhdx'
            Os       = 'windows'
            Cpus     = 4
            MemoryGB = 8
            OsDiskGB = 80
            VlanId   = 20
            Tpm      = $true
        }
        'lab-db01'  = @{
            Image  = 'debian13-20261115-a1b2c3d.vhdx'
            Os     = 'linux'
            Disk   = 'Differencing'
            SshKey = 'ssh-ed25519 AAAA… admin@lab'
        }
    }
}
```

- Read it with `Import-PowerShellDataFile`, which runs no code, never with `.` or
  `Invoke-Expression`.
- The fields match Terraform's `vms` map, so a VM can move between the tools.
- Check every value before the first change, and reject a key you do not know.
  Terraform drops a misspelled optional attribute and quietly takes the default; a
  script can stop instead:

  ```powershell
  foreach ($key in $vm.Keys) {
      if (-not $VmDefaults.Contains($key)) { $problems.Add("${where}: unknown setting '$key'") }
  }
  ```

  Collect every problem, then throw once with all of them, so one run shows every typo.
- Nothing secret in the file. The local Administrator password is a `[pscredential]`
  parameter; a Linux VM gets a public key.

## 3. Check the host before changing anything

- The switch exists: `Get-VMSwitch | Where-Object Name -EQ $SwitchName`.
- Every image exists: `Test-Path -LiteralPath $image -PathType Leaf`.
- `OsDiskGB` is at least the image's size (`(Get-VHD -Path $image).Size`): a disk can
  only grow.
- A Windows VM has the credential it needs.

All of it before the first VM is touched, so a typo stops the run instead of half of it.
Find a VM with `Get-VM | Where-Object Name -EQ $name`: `Get-VM -Name` reads the name as a
wildcard pattern.

## 4. Making a VM

1. **Its own folder**, `<VmRoot>\<name>`. If the folder exists but the VM does not,
   stop: something is left from an earlier run, and a person should look at it.
2. **The OS disk** from the image, with the rules of `references/hyperv.md`:
   - Copy (the default): `Copy-Item`, then clear the read-only flag. The copy keeps the
     image's flag, and Hyper-V cannot start a VM from a read-only disk. `Resize-VHD`
     grows it to `OsDiskGB`.
   - Differencing: `New-VHD -ParentPath $image -Differencing`, for short-lived VMs only.
     The image must stay unchanged for as long as the VM exists.
3. **First-boot files**, with the same content as Terraform's seed:
   - **Windows:** mount the OS disk, write `Unattend.xml` (computer name, time zone,
     Administrator password) into its `C:\Windows\Panther`, which Setup reads first,
     and dismount in `finally`. While it is mounted, grow the Windows partition to
     `Get-PartitionSupportedSize`'s `SizeMax`, so the guest needs no step to use a
     larger disk. Escape every value with `[Security.SecurityElement]::Escape()`.
   - **Linux:** a 64 MB VHDX, FAT32, labelled `CIDATA`, holding `meta-data` and
     `user-data`, attached as a second disk. cloud-init's NoCloud source finds it by the
     label. Windows Server ships no tool that makes an ISO (`oscdimg` is in the ADK),
     but it makes this disk with its own Storage cmdlets. Write `user-data` as JSON
     after the `#cloud-config` line: JSON is YAML, and no value needs quoting.
   - `instance-id` comes from the VM name and its image, never from a timestamp:
     cloud-init runs again whenever it changes.
4. **The VM:**

   ```powershell
   $vm = New-VM -Name $name -Generation 2 -MemoryStartupBytes ($spec.MemoryGB * 1GB) `
       -VHDPath $osDisk -SwitchName $SwitchName -Path $VmRoot  # its config goes in its folder
   Set-VMProcessor -VM $vm -Count $spec.Cpus
   Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
   Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate $template `
       -FirstBootDevice (Get-VMHardDiskDrive -VM $vm)        # before the seed disk is added
   Set-VM -VM $vm -CheckpointType Disabled -AutomaticStartAction StartIfRunning `
       -AutomaticStopAction ShutDown -Notes (ConvertTo-VMNote -Spec $spec)
   ```

   The secure boot template is `MicrosoftWindows` or `MicrosoftUEFICertificateAuthority`
   (Linux), matching the image. Then the VLAN (`Set-VMNetworkAdapterVlan -Access`), a
   static MAC if a DHCP reservation needs one, and the TPM (`Set-VMKeyProtector
   -NewLocalKeyProtector`, then `Enable-VMTPM`): a new VM is off, the one time a new key
   protector is always safe. Then `Start-VM`.
5. **If a step fails**, remove the half-made VM and its folder in `catch`, then throw
   again. The folder did not exist before this run, so everything in it is this run's,
   and the next run starts clean.

The notes hold the owner and the settings that are fixed once the VM exists:

```
Managed-by: hyperv-deploy
Image: win2025-20261115-a1b2c3d.vhdx
Disk: Copy
OsDiskGB: 80
```

## 5. Changing a VM

Read what is there (`Get-VM`: `ProcessorCount`, `MemoryStartup`, `Notes`, `State`; the
adapter; its VLAN; `Get-VMSecurity`), compare it with the data file, and sort each
difference by what it needs:

| Kind | Settings | What the script does |
|---|---|---|
| Online | switch, VLAN | Applies it while the VM runs |
| Offline | processors, memory, MAC, turning the TPM on | Needs the VM off: with `-AllowRestart`, a shutdown and a start; without it, stops and says so |
| Refuse | image, disk kind, disk size, turning the TPM off | Stops with what to do instead |

- A new image means a new VM: remove it and deploy it again. Never swap the disk under a
  VM; the data file says which image each VM runs.
- Turning the TPM off loses everything the guest sealed with it. A person does that.
- `Stop-VM -Force` is a shutdown through the guest; `-Force` only skips the prompt a
  locked VM raises, which would fail an unattended run. `-TurnOff` pulls the plug, and
  is only for a VM being deleted. Start the VM again in `finally`, so a failed change
  does not leave it off.
- The `ShouldProcess` message lists every change (`Cpus 2 -> 4, VlanId -> 20 (restarts
  the VM)`). Under `-WhatIf` that list is the plan.
- A VM with no differences is reported with `Changed = $false`, and nothing is called.

## 6. Removing a VM

A separate script with `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]`,
so it asks before each VM unless the caller passes `-Confirm:$false` on purpose.

- It refuses a VM whose notes do not name this script, and a VM with any disk outside
  its own folder: a shared or data disk elsewhere is not the script's to delete.
- It turns the VM off, removes it, and deletes its folder, nothing else. One folder per
  VM, holding only that VM's files, is what makes that safe.
- A VM that is not there is reported, not an error, so a second run changes nothing.

## 7. Credentials

- `-LocalAdminCredential` comes from `Get-Credential` on the host or from masked CI
  variables (`powershell`, section 6).
- The password ends up in clear text in `Unattend.xml` inside the VM's disk, as it does on
  Terraform's seed ISO. Use one that Ansible changes on its first run, never a domain or
  service password.

## 8. Tests

Pester, with every Hyper-V and Storage cmdlet mocked (see the `powershell` skill for the
stand-in module that makes mocking possible on Linux). The cases that matter:

- an empty host gets every VM, with the right disk, first-boot files, and TPM;
- `-WhatIf` calls no command that changes anything;
- a second run on a host that matches the data file calls none either;
- a missing image stops the run before the first change;
- an Offline change needs `-AllowRestart`, and a Refuse change stops;
- a VM the script did not make is refused, by both scripts;
- a failed create removes what it made.

What made the mocks work, in Pester 6 on Linux:

- A call that matches none of a command's parameter filters fails; it does not fall back
  to the real command. Give the command a default mock without a filter.
- That default must not call the command itself, even module-qualified
  (`Microsoft.PowerShell.Management\Test-Path`): Pester mocks that name too, and the
  test hangs. Use .NET (`[IO.File]::Exists($LiteralPath)`).
- `Join-Path`, and `Set-Content`'s `-Encoding`, need the drive in the path to exist. Make
  `D:` and the mocked disks' letters with `New-PSDrive -PSProvider FileSystem`.
- `Join-Path` writes `/` on Linux, so filters match `'D:?VMs*'`.
- A mock that returns nothing ends a pipeline. Every mocked command in a chain
  (`Mount-VHD | Get-Disk`, `Initialize-Disk | New-Partition | Format-Volume`) returns an
  object.
- State shared between mocks goes in a hashtable captured with `.GetNewClosure()`;
  `$script:` in a mock body is not the test file's scope.

## Before calling it done

```
Invoke-ScriptAnalyzer -Path <file> -Severity Warning, Error    # every script and the module
Invoke-Pester -Path . -Output Detailed
./Deploy-HyperVVM.ps1 -ConfigPath envs/<env>.psd1 -LocalAdminCredential $cred -WhatIf
./Deploy-HyperVVM.ps1 -ConfigPath envs/<env>.psd1 -LocalAdminCredential $cred
./Deploy-HyperVVM.ps1 -ConfigPath envs/<env>.psd1 -LocalAdminCredential $cred   # all Changed False
```

On the host, read every `What if:` line before the real run. Then check one new VM's
first boot: a Windows VM took the computer name and did not stop at the password page; a
Linux VM shows `cloud-init status --long` as `done` and has its hostname. Then run the
`powershell-reviewer` agent on the scripts and the module (in Codex, the
`powershell-review` skill).
