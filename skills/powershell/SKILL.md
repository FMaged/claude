---
name: powershell
description: Use when writing or changing PowerShell — a script, a function, or a module — for Windows servers, the Hyper-V host, CI jobs, or Packer provisioners — strict mode and error handling, -WhatIf and ShouldProcess, changes that are safe to run twice, parameters and validation, credentials, remoting, the Hyper-V module for what Terraform cannot set (a virtual TPM, trunk VLANs), module manifests, Pester tests, and PSScriptAnalyzer (e.g. "write a powershell script that…", "add -WhatIf to this function", "make this script safe to run twice", "give the VM a virtual TPM", "write Pester tests for this script", "why does my script keep going after an error"). For creating whole Hyper-V VMs without Terraform, use hyperv-deploy instead.
---

# PowerShell

A PowerShell script on a server runs unattended and changes real machines, so write it
to stop at the first error, to change nothing under `-WhatIf`, and to change nothing on
a second run. Most PowerShell trouble is a script that kept going after a failure, a
`-WhatIf` that still changed something, or a step that worked once and broke the rerun.

Creating and changing whole Hyper-V VMs without Terraform is the `hyperv-deploy` skill.
For comments, `code-comments`.

## 0. Which PowerShell runs the script

| Where it runs | Version | `#Requires` |
|---|---|---|
| The Hyper-V host, a Windows runner, your PC | PowerShell 7 (`pwsh`) | `#Requires -Version 7.2` |
| Inside a fresh Windows guest, a Packer provisioner, a first-boot command | Windows PowerShell 5.1 (`powershell.exe`), the only one Windows ships | `#Requires -Version 5.1` |
| A Linux runner | PowerShell 7, without the Windows modules | `#Requires -Version 7.2` |

Write for the version that will run it. Not in 5.1: `??`, `?:`, `&&` and `||` between
commands, `ForEach-Object -Parallel`, `$PSNativeCommandUseErrorActionPreference`, and
UTF-8 without a BOM as the default encoding (5.1's `-Encoding utf8` writes a BOM, and
`Out-File` writes UTF-16). A file a Linux tool or cloud-init reads, written from 5.1,
needs `[IO.File]::WriteAllText($path, $text)`, which writes UTF-8 without a BOM.

## 1. Stop at the first error

Every script starts with:

```powershell
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

- `Stop` turns every error from a cmdlet into one that ends the script. Without it, a
  failed `New-Item` prints red text and the next line runs anyway.
- `Set-StrictMode -Version Latest` fails on a variable that was never set and on a
  property that does not exist, instead of reading `$null`. To ask whether an object has
  a property, use `$obj.PSObject.Properties.Name -contains 'X'`.
- **Native programs ignore both.** After `sc.exe`, `dism.exe`, `netsh`, or `git`, check
  `$LASTEXITCODE`:

  ```powershell
  dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart
  if ($LASTEXITCODE -notin 0, 3010) { throw "DISM failed with exit code $LASTEXITCODE" }
  ```

  In PowerShell 7.4 and later, `$PSNativeCommandUseErrorActionPreference = $true` makes
  a non-zero exit code throw. Not in 5.1.
- **A GUI program is not waited for.** Called with `&`, `sysprep.exe` or an installer
  returns at once and `$LASTEXITCODE` means nothing. Use
  `Start-Process -FilePath … -ArgumentList … -Wait -PassThru` and check `.ExitCode`.
- `try`/`catch` only where the script can do something about the error: clean up, start
  a VM it stopped, try another way. A `catch` that writes a message and carries on hides
  the failure. `finally` is for undoing what the script changed before the error.
- `-ErrorAction SilentlyContinue` hides every error, including access denied, so a probe
  that uses it reads "not there" when the truth is "not allowed". Find things with a
  filter instead (section 3), and never put it on a command that changes something.
- `exit` with a number only in a script that a program runs; in a function, `throw`. An
  uncaught `throw` in `pwsh -File script.ps1` exits with 1, which fails the CI job.

## 2. Parameters

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{0,14}$')]
    [string[]] $Name,

    [ValidateSet('Windows', 'Linux')]
    [string] $OperatingSystem = 'Windows',

    [ValidateRange(1, 64)]
    [int] $ProcessorCount = 2,

    [pscredential] $Credential,

    [switch] $AllowRestart
)
```

- Every parameter has a type, and a validation attribute wherever a wrong value would
  fail late, in the middle of a change on a host.
- `[switch]`, never `[bool]`, for an on/off choice.
- A script param block with `[CmdletBinding()]` gets `-Verbose`, `-ErrorAction`, and,
  with `SupportsShouldProcess`, `-WhatIf` and `-Confirm`.
- Long calls are splatted, so each argument is on its own line:

  ```powershell
  $vmArgs = @{
      Name               = $vmName
      Generation         = 2
      MemoryStartupBytes = 4GB
      SwitchName         = $SwitchName
  }
  New-VM @vmArgs
  ```

## 3. Safe to run twice

Read the current state, compare it with what you want, change only the difference.

```powershell
foreach ($vmName in $Name) {
    # Get-VM -Name treats the name as a wildcard pattern; a filter compares it exactly.
    $vm = Get-VM | Where-Object Name -EQ $vmName
    if (-not $vm) { throw "VM $vmName does not exist on this host." }

    if ((Get-VMSecurity -VM $vm).TpmEnabled) {
        [pscustomobject]@{ VM = $vmName; Changed = $false; Action = 'TPM already on' }
        continue
    }
    # … the change, inside a ShouldProcess check (section 4)
}
```

- `Get-` before `New-`, `Set-`, or `Remove-`. A second run that finds everything in
  place changes nothing, says so, and exits with 0.
- Exit codes say whether the script worked, not whether it changed something. To report
  changes, output an object per thing with a `Changed` property.
- A change that needs the machine off or restarted is never done quietly. Ask for it
  with a switch (`-AllowRestart`), and without it, throw with a message that says what
  to do. Shut a VM down with `Stop-VM -Force`: that is still a shutdown through the
  guest, and `-Force` only skips the prompt a locked VM raises, which would fail an
  unattended run. `-TurnOff` pulls the plug. Start it again in `finally`.

## 4. `-WhatIf` that really changes nothing

```powershell
if ($PSCmdlet.ShouldProcess($vmName, 'Turn on a virtual TPM with a new local key protector')) {
    Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
    Enable-VMTPM -VM $vm
}
```

- Put every change inside a `ShouldProcess` check, one per change a person would want to
  see. Under `-WhatIf` it prints `What if: Performing the operation "…" on target "…"`
  and returns `$false`.
- Do not rely on `-WhatIf` reaching the cmdlets you call. It reaches cmdlets in the same
  script, but not native programs, not `Invoke-Command` script blocks, not most .NET
  calls, and not every module. The explicit check covers all of them.
- The reads before the check run under `-WhatIf` too, so the preview shows what would
  really change, not every possible change.
- Something that deletes or cannot be undone gets
  `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]`, so it asks even
  without `-Confirm`. CI passes `-Confirm:$false` on purpose, in the job file.
- Test `-WhatIf` (section 8): a run with `-WhatIf` calls no `New-`, `Set-`, `Remove-`,
  `Enable-`, `Start-`, or `Stop-` cmdlet.

## 5. Output

- Results are objects on the pipeline (`[pscustomobject]@{ … }`), so a caller can filter
  them or turn them into JSON. One object type per script.
- Progress for people is `Write-Verbose` (shown with `-Verbose`) or `Write-Information`.
  `Write-Host` only in an interactive tool: it is text for a person, not output a caller
  can use.
- Nothing else leaks into the output. Cmdlets like `New-Item` and `Add-Member`, and
  methods like `List.Add()`, return values; discard them with `$null = …`.
- `Write-Warning` for something a person should look at; `throw` for a failure.

## 6. Credentials

- A credential is a `[pscredential]` parameter. Functions take it and pass it on; they
  never build it from parts.
- In CI, build it once at the entry point from masked variables:

  ```powershell
  $secure = ConvertTo-SecureString -String $env:HYPERV_PASSWORD -AsPlainText -Force
  $credential = [pscredential]::new($env:HYPERV_USER, $secure)
  ```

  This is the one accepted use of `-AsPlainText`: from an environment variable, never
  from a literal in the file. Tell PSScriptAnalyzer so with a `SuppressMessageAttribute`
  on that script's `param` block, with the reason as `Justification`.
- On a PC, `Get-Credential` or the SecretManagement module (`Get-Secret`), never a
  password in a file or in history.
- `SecureString` is not encryption on Linux, and it is plain text again the moment a
  native program needs it. It keeps a password out of logs and transcripts; that is all.
- Never `Start-Transcript` in a script that handles secrets, and never write a credential
  object with `Write-Verbose`.

## 7. Remoting and the Hyper-V host

- Prefer running on the host: the Hyper-V module needs the host, and the `hyperv` runner
  tag runs the job there. From another Windows machine, `Invoke-Command -ComputerName`
  over WinRM with Kerberos.
- From a Linux runner, PowerShell remoting over WinRM is not supported. Use SSH remoting
  (`Invoke-Command -HostName … -UserName …`, with OpenSSH on the host) or move the job to
  the `hyperv` tag.
- A remote script block runs in a fresh session: `$ErrorActionPreference`, StrictMode,
  `-WhatIf`, and your variables do not reach it. Set the first two inside it, pass
  values with `-ArgumentList` or `$using:`, and do the `ShouldProcess` check outside.
- One session for many calls: `New-PSSession`, then `Remove-PSSession` in `finally`.
- The second hop fails: a remote session cannot use your Kerberos ticket to reach a
  file share. Copy files to the host first, or set up resource-based constrained
  delegation. Not CredSSP.

What the Terraform provider cannot set is a PowerShell step that runs after the apply,
as its own pipeline job (`terraform/references/hyperv.md`, "What the provider cannot do"):

- **Virtual TPM:** `Set-VMKeyProtector -NewLocalKeyProtector`, then `Enable-VMTPM`, with
  the VM off. Never set a new key protector on a VM whose TPM is already on: the guest
  loses everything its TPM sealed, and BitLocker asks for the recovery key. A local key
  protector ties the VM to the host's `UntrustedGuardian`; before the VM can move to
  another host, that host needs the same guardian's certificates.
- **Trunk VLANs:** `Set-VMNetworkAdapterVlan -Trunk -AllowedVlanIdList … -NativeVlanId …`.
- Cluster roles (`Add-ClusterVirtualMachineRole`), Hyper-V Replica, `Copy-VMFile` into a
  running guest, and the host's own network and storage.

Never set from a script what the provider already manages: memory, processors (nested
virtualization included), firmware, integration services, adaptors, disks. The next
plan shows it as drift and reverts it.

## 8. Modules, tests, and analysis

- A function used by more than one script goes in a module: `Name.psm1` plus a manifest
  `Name.psd1` with `ModuleVersion`, `RootModule`, `FunctionsToExport` as an explicit list
  (never `*`), and `RequiredModules` with versions.
- Install modules at a pinned version in CI (`Install-PSResource -Name X -Version 1.2.3`,
  or `Install-Module -RequiredVersion` on 5.1). An unpinned module changes under a
  pipeline that did not change.
- Function names use an approved verb (`Get-Verb`) and a singular noun. No aliases
  (`%`, `?`, `ls`) and no positional arguments past the first in scripts.
- `-LiteralPath` and `Join-Path` for paths: `-Path` treats `[` and `*` as wildcards.

**Pester** (`Name.Tests.ps1` next to the script). Mock every cmdlet that touches a
machine, and test the four cases that matter: nothing to do changes nothing, a change is
made once, `-WhatIf` changes nothing, a failure leaves things as they were.

```powershell
BeforeAll {
    # Pester can mock only commands that exist. On a machine without Hyper-V, a stand-in
    # module gives the names, and #Requires -Modules Hyper-V finds it loaded.
    New-Module -Name Hyper-V -ScriptBlock {
        function Get-VM { }
        function Enable-VMTPM { param($VM) }
    } | Import-Module
    $script = Join-Path $PSScriptRoot 'Add-VMVirtualTpm.ps1'
}

It 'changes nothing under -WhatIf' {
    Mock Get-VM { [pscustomobject]@{ Name = 'web01'; State = 'Off'; Generation = 2 } }
    Mock Enable-VMTPM { }
    & $script -Name web01 -WhatIf
    Should -Invoke Enable-VMTPM -Times 0 -Exactly
}
```

**PSScriptAnalyzer:** `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning, Error`
must report nothing. Suppress a rule only on the line or block it is wrong about, with a
`Justification`, never in a settings file for the whole repo.

## Before calling it done

```
Invoke-ScriptAnalyzer -Path <folder> -Recurse -Severity Warning, Error
Invoke-Pester -Path <folder> -Output Detailed
pwsh -NoProfile -NonInteractive -File <script> <args> -WhatIf
```

Run it once with `-WhatIf` against the real host and read every `What if:` line; then for
real; then a second time, which must report nothing changed. `-NonInteractive` makes a
prompt fail instead of hanging a CI job.
