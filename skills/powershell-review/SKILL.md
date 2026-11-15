---
name: powershell-review
description: Use when reviewing PowerShell — a script, a function, a module, a Pester test, or a Hyper-V deploy script (e.g. "review my powershell script", "check this .ps1", "is this script safe to run on the Hyper-V host?", "does -WhatIf really change nothing here?", "is a second run of this deploy script a no-op?"). Reports what fails silently, what changes the host under -WhatIf or on a re-run, and what leaks secrets, with the file and line.
---

# PowerShell Review

Review `.ps1`, `.psm1`, `.psd1`, and `.Tests.ps1` files, and PowerShell inside CI job
files and Packer provisioners. Report problems. Do not rewrite unless the user asks.

A PowerShell script on a server runs unattended against real machines. What matters most
is a script that keeps going after a failure, a `-WhatIf` that still changes something, a
second run that changes or breaks something, and a secret in a file or a log. The writing
rules are in the `powershell` skill; scripts that make Hyper-V VMs follow `hyperv-deploy`.

## 1. What fails silently

- No `$ErrorActionPreference = 'Stop'` at the top of a script. A failed cmdlet prints red
  text and the next line runs anyway.
- `-ErrorAction SilentlyContinue` or `Ignore`. On a command that changes something, it
  hides the failure. On a probe (`Get-VM`, `Get-Item`, `Get-Service`), "access denied"
  reads as "not there", and the script goes on to create what already exists. A filter
  (`Get-VM | Where-Object Name -EQ $name`) or `Test-Path -LiteralPath` is the fix.
- A native program (`dism.exe`, `sc.exe`, `netsh`, `git`) with no `$LASTEXITCODE` check
  after it: `Stop` does not reach native programs. Also a check that accepts only 0 where
  the program has other success codes (3010, reboot needed, for DISM and MSI).
  `$PSNativeCommandUseErrorActionPreference = $true` is fine from 7.4, not in 5.1.
- A GUI program or installer started with `&` (`sysprep.exe`, `setup.exe`, `msiexec`). It
  returns at once and `$LASTEXITCODE` means nothing. It needs
  `Start-Process -Wait -PassThru` and a check of `.ExitCode`.
- A `catch` that writes a message and carries on, or one around the whole script that
  ends it with exit code 0: the CI job is green after a failure. A `catch` is right only
  when it cleans up, tries another way, or throws again.

## 2. What changes the host under `-WhatIf`

A person runs `-WhatIf` on production to see the plan. Anything it changes is a blocker.

- A script that changes something with no `[CmdletBinding(SupportsShouldProcess)]`: there
  is no preview at all.
- A change with no `$PSCmdlet.ShouldProcess` check above it, trusting `-WhatIf` to reach
  it. It does not reach native programs, `Invoke-Command` script blocks on another
  machine, .NET calls (`[IO.File]::WriteAllText`, `[IO.Directory]::Delete`), COM, or every
  module's functions. Trace each change in the script to the check that guards it.
- A step that looks like a read but changes the host, run before the check: `Mount-VHD`
  to look inside a disk, `New-Item` for a working folder, `Copy-Item` of an image,
  `Install-Module`.
- Output that reports `Changed = $true` for a change that `ShouldProcess` skipped.
- A `ShouldProcess` message that does not say what will happen ("Process VM" instead of
  "Cpus 2 -> 4 (restarts the VM)"), so the preview cannot tell a restart from a no-op.
- `ShouldProcess` inside a remote script block, where `-WhatIf` does not arrive and no
  person can answer a prompt.
- A delete, or anything that cannot be undone, without `ConfirmImpact = 'High'`; or
  `-Confirm:$false` written into the script instead of passed by the caller.

## 3. What breaks a second run

- `New-` with no `Get-` before it: the second run fails with "already exists", or makes
  a second one.
- A comparison that never matches, so every run changes again: different units
  (`MemoryStartup` is in bytes, the data file says GB), `$null` against an empty string or
  an empty array, or a case-sensitive comparison (`-ceq`, `.Equals()`, `.StartsWith()`
  without `OrdinalIgnoreCase`) where Hyper-V returns another case.
- `Get-VM -Name`, `Get-Service -Name`, or `-Path`, which read the value as a wildcard: a
  name or path with `*`, `?`, or `[` matches other things. A filter, or `-LiteralPath`.
- A value that is new on every run where something compares it: a timestamp or random
  part in a cloud-init `instance-id` (cloud-init runs again), or in a file the script
  writes and then compares.
- A restart done quietly: a change that needs the VM off, with no `-AllowRestart` switch
  and no throw without it. `Stop-VM` without `-Force` in an unattended script: it prompts
  on a locked VM, so the run fails under `-NonInteractive` or hangs without it.
  `Stop-VM -TurnOff` on a VM that is not being deleted pulls the plug. A VM stopped for a
  change and not started again in `finally`.
- A script that sets what the Terraform provider manages (memory, processors, firmware,
  integration services, adaptors, disks). The next plan reverts it, every time.
- An exit code that says whether something changed rather than whether it worked, so CI
  fails on "nothing to do".

## 4. Hyper-V deploy scripts

For scripts that create, change, or remove VMs (`hyperv-deploy`), check also:

- **Owner.** Every change and every removal checks the VM's notes for
  `Managed-by: hyperv-deploy` first, not only the create. A script that changes a VM made
  by Terraform or by hand is the worst finding here: two tools now undo each other.
- **The data file.** Read with `Import-PowerShellDataFile`, never with `.` or
  `Invoke-Expression`, which run whatever the file holds. Unknown keys are rejected, and
  every value, the images, the switch, and the disk sizes are checked before the first
  change. A check inside the per-VM loop lets the first VMs change before a later typo
  stops the run.
- **Deletes.** `Remove-Item -Recurse` only on the VM's own folder, with `-LiteralPath`.
  `Join-Path $VmRoot $name` with an empty or `$null` name returns `$VmRoot` itself, so a
  missing value deletes every VM's files; the name needs a `ValidatePattern` or a check.
  The check that every disk is inside the folder needs the separator:
  `StartsWith("$folder\")`, because `StartsWith($folder)` also accepts `D:\VMs\web010`.
- **Changes it must refuse.** A new image, disk kind, or disk size applied to an existing
  VM instead of refused. A new key protector (`Set-VMKeyProtector -NewLocalKeyProtector`)
  on a VM whose TPM is already on: the guest loses what it sealed, and BitLocker asks for
  the recovery key.
- **A failed create.** It removes the half-made VM and its folder in `catch` and throws
  again. A disk mounted to write first-boot files is dismounted in `finally`.
- **First-boot files.** A value written into `Unattend.xml` without
  `[Security.SecurityElement]::Escape()`: a `&` or `<` in the password makes the file
  invalid, and Setup stops.

## 5. Secrets

- A password, token, or key as a literal in a script or a data file. Obvious fakes in
  tests are fine.
- `ConvertTo-SecureString -AsPlainText` from a literal. From an environment variable at
  the script's entry point is the one accepted use (`powershell`, section 6), and its
  analyzer suppression needs a `Justification`.
- A `[string] $Password` parameter instead of `[pscredential]`: it lands in history, in
  transcripts, and in the CI job's command line. A credential built from parts inside a
  function instead of passed in.
- A secret that reaches a log: `Start-Transcript` in a script that handles secrets;
  `Write-Verbose`, `Write-Host`, or output of a credential or a string built from one; a
  password on a native program's command line (`net user`, `cmdkey /pass:`), which shows
  in the process list and the job log.
- `Get-Credential` or `Read-Host` in a script that runs unattended. It hangs, or fails
  under `-NonInteractive`.
- A local Administrator password in `Unattend.xml` that is anything but a throwaway that
  Ansible changes on its first run.

## 6. StrictMode, versions, and remoting

- No `Set-StrictMode -Version Latest`. A misspelled variable then reads `$null`, and the
  script acts on the wrong thing without a word.
- Reads that throw under StrictMode when data is sometimes missing (checked in
  PowerShell 7.7):
  - `.Count` on a result that can be empty: `(Get-VM | Where-Object …).Count` throws
    when nothing matches. `@(…).Count` does not.
  - An optional key read with a dot: `$spec.Disk` throws when the hashtable has no
    `Disk`. `$spec['Disk']` or `$spec.ContainsKey('Disk')` does not.
  - A property only some objects have: `$obj.PSObject.Properties.Name -contains 'X'`.
- `#Requires -Version 7.2`, or 7-only syntax (`??`, `?:`, `&&` and `||` between commands,
  `ForEach-Object -Parallel`), in a script that runs inside a guest or a Packer
  provisioner, where only Windows PowerShell 5.1 exists. In 5.1, `Out-File` writes UTF-16
  and `-Encoding utf8` writes a BOM, which breaks a file cloud-init or a Linux tool reads.
- A remote script block (`Invoke-Command -ComputerName`, `-Session`, `-HostName`) that
  relies on the caller's `$ErrorActionPreference`, StrictMode, `-WhatIf`, or variables.
  It runs in a fresh session: it sets the first two itself and gets values through
  `$using:` or `-ArgumentList`.
- A second hop: a remote session that reads a file share with the caller's Kerberos
  ticket fails with access denied. CredSSP as the fix is a finding of its own.
- `New-PSSession` without `Remove-PSSession` in `finally`. WinRM remoting from a Linux
  runner, which is not supported: SSH remoting, or the job on the `hyperv` runner.

## 7. Modules and pinning

- `Install-Module` or `Install-PSResource` without a version in CI or a provisioner. An
  unpinned module changes under a pipeline that did not change.
- A manifest with `FunctionsToExport = '*'`, or `RequiredModules` without versions.
- An analyzer rule turned off for the whole repo in a settings file, instead of
  suppressed on the line or block with a `Justification`.

## 8. Tests

- No test for `-WhatIf`, for a second run, or for a failure. The four cases are in the
  `powershell` skill, section 8.
- A Hyper-V or Storage cmdlet the script calls but the test does not mock. On the host,
  that test changes the host.
- `Should -Invoke … -Times 1` without `-Exactly`, which means "at least once": the test
  passes when the change runs twice.

## Commands

```
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning, Error
Invoke-Pester -Path . -Output Detailed
pwsh -NoProfile -NonInteractive -File <script> <args> -WhatIf
```

Skip what PSScriptAnalyzer reports on its own (aliases, unapproved verbs, a plain-text
password parameter, `Write-Host`); say "run `Invoke-ScriptAnalyzer`" in one line instead
of listing them. A `-WhatIf` run on the host is the only proof that the preview changes
nothing; Pester with mocks shows which commands a run calls.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it does to the host>
Fix: <the change, one line>
```

A blocker changes what it should not (under `-WhatIf`, on a VM it does not own, outside
its folder), keeps going after a failure, or leaks a secret. A should-fix breaks a
re-run, breaks under StrictMode or 5.1, or makes the preview unreadable. A nit is
tidiness. If the code is fine, say so in one sentence and name the two or three things you
checked hardest. Do not invent findings to fill a list. If you add a comment as part of a
fix, follow the `code-comments` skill.
