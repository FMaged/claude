#Requires -Version 7.2
#Requires -Modules Hyper-V
<#
.SYNOPSIS
Gives Hyper-V VMs a virtual TPM: a new local key protector, then the TPM.

.DESCRIPTION
Runs on the Hyper-V host as its own pipeline step after terraform apply, because the
taliesins/hyperv provider cannot set a TPM. Safe to run again: a VM whose TPM is
already on is left alone. The TPM can be turned on only while the VM is off, so a
running VM needs -AllowRestart; without it the script stops and says so.

Outputs one object per VM with VM, Changed, and Action.

.EXAMPLE
./Add-VMVirtualTpm.ps1 -Name web01, web02 -AllowRestart -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{0,14}$')]
    [string[]] $Name,

    # Shut a running VM down through the guest, turn the TPM on, and start it again.
    [switch] $AllowRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($vmName in $Name) {
    # Get-VM -Name treats the name as a wildcard pattern; a filter compares it exactly.
    $vm = Get-VM | Where-Object Name -EQ $vmName
    if (-not $vm) { throw "VM $vmName does not exist on this host." }
    if ($vm.Generation -ne 2) { throw "VM $vmName is generation $($vm.Generation); a virtual TPM needs generation 2." }

    if ((Get-VMSecurity -VM $vm).TpmEnabled) {
        [pscustomobject]@{ VM = $vmName; Changed = $false; Action = 'none: the TPM is already on' }
        continue
    }

    $wasRunning = $vm.State -ne 'Off'
    if ($wasRunning -and -not $AllowRestart) {
        throw "VM $vmName is $($vm.State). The TPM can be turned on only while it is off: stop it, or run again with -AllowRestart."
    }

    $action = if ($wasRunning) { 'Restart and turn on a virtual TPM' } else { 'Turn on a virtual TPM' }
    if (-not $PSCmdlet.ShouldProcess($vmName, $action)) { continue }

    if ($wasRunning) { Stop-VM -VM $vm } # through the guest's shutdown, not -Force
    try {
        # A new key protector is safe only here, while the TPM is off. On a VM whose TPM
        # is on it would throw away everything the guest sealed, BitLocker keys included.
        Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
        Enable-VMTPM -VM $vm
    }
    finally {
        if ($wasRunning) { Start-VM -VM $vm }
    }
    [pscustomobject]@{ VM = $vmName; Changed = $true; Action = $action }
}
