#Requires -Version 7.2
#Requires -Modules Hyper-V
<#
.SYNOPSIS
Deletes VMs that Deploy-HyperVVM.ps1 made: the VM and its own folder, nothing else.

.DESCRIPTION
Runs on the Hyper-V host. Asks before each VM unless -Confirm:$false is passed. Refuses a
VM whose notes do not say hyperv-deploy made it, and a VM with a disk outside its own
folder. A VM that is not there is reported, not an error, so a second run is a no-op.

.EXAMPLE
./Remove-HyperVVM.ps1 -ConfigPath envs/lab.psd1 -Name lab-db01 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ConfigPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{0,14}$')]
    [string[]] $Name
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'HyperVDeploy.psd1') -Force

$config = Import-DeployConfig -Path $ConfigPath

foreach ($vmName in $Name) {
    $vm = Get-VM | Where-Object Name -EQ $vmName
    if (-not $vm) {
        [pscustomobject]@{ VM = $vmName; Changed = $false; Actions = @('not on this host') }
        continue
    }
    Assert-ManagedVM -VM $vm

    $folder = Join-Path -Path $config.VmRoot -ChildPath $vmName
    $outside = @(Get-VMHardDiskDrive -VM $vm | Where-Object { -not $_.Path.StartsWith("$folder\", [StringComparison]::OrdinalIgnoreCase) })
    if ($outside) { throw "VM $vmName has disks outside ${folder}: $($outside.Path -join ', '). Detach them by hand first." }

    if (-not $PSCmdlet.ShouldProcess($vmName, "Delete the VM and everything in $folder")) { continue }
    if ($vm.State -ne 'Off') { Stop-VM -VM $vm -TurnOff -Force } # it is being deleted; nothing in it is kept
    Remove-VM -VM $vm -Force
    Remove-Item -LiteralPath $folder -Recurse -Force
    [pscustomobject]@{ VM = $vmName; Changed = $true; Actions = @('deleted') }
}
