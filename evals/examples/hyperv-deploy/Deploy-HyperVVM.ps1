#Requires -Version 7.2
#Requires -Modules Hyper-V
<#
.SYNOPSIS
Creates and updates the Hyper-V VMs an environment's data file lists, without Terraform.

.DESCRIPTION
Runs on the Hyper-V host. Reads the data file, checks every value and the host (switch,
images) before any change, then for each VM:
- missing: makes it from the Packer image with its first-boot files and starts it;
- present: lists each difference from the data file and applies it.

-WhatIf is the plan: it prints what would change and changes nothing. A second run with
no changes to the data file changes nothing. Changes that need the VM off need
-AllowRestart. The script changes only VMs whose notes say it made them.

Outputs one object per VM with VM, Changed, and Actions.

.EXAMPLE
./Deploy-HyperVVM.ps1 -ConfigPath envs/lab.psd1 -LocalAdminCredential (Get-Credential Administrator) -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ConfigPath,

    # Only these VMs from the data file. Default: all of them.
    [string[]] $Name,

    # The local Administrator password a new Windows VM gets. Ansible changes it on its first run.
    [pscredential] $LocalAdminCredential,

    # Shut a running VM down to apply a change that needs it off, then start it again.
    [switch] $AllowRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'HyperVDeploy.psd1') -Force

function Write-AnswerFile {
    # Writes Unattend.xml into the OS disk's C:\Windows\Panther, which a clone's Setup reads
    # first, and grows the Windows partition to fill the disk while it is mounted.
    param([string] $DiskPath, [string] $Content)

    $disk = Mount-VHD -Path $DiskPath -Passthru | Get-Disk
    try {
        $basicData = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
        $partition = @(Get-Partition -DiskNumber $disk.Number | Where-Object GptType -EQ $basicData)
        if ($partition.Count -ne 1) { throw "$DiskPath has $($partition.Count) Windows partitions, expected 1." }
        $number = $partition[0].PartitionNumber
        $max = (Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $number).SizeMax
        if ($partition[0].Size -lt $max) { Resize-Partition -DiskNumber $disk.Number -PartitionNumber $number -Size $max }
        if ("$($partition[0].DriveLetter)" -notmatch '^[A-Z]$') {
            Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $number -AssignDriveLetter
        }
        $letter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $number).DriveLetter
        $panther = "${letter}:\Windows\Panther"
        $null = New-Item -ItemType Directory -Path $panther -Force
        Set-Content -LiteralPath (Join-Path -Path $panther -ChildPath 'Unattend.xml') -Value $Content -Encoding utf8NoBOM
    }
    finally {
        Dismount-VHD -Path $DiskPath
    }
}

function Initialize-SeedDisk {
    # A small FAT32 disk labelled CIDATA, which cloud-init's NoCloud source finds by its
    # label. Windows Server has no tool to make an ISO, but it can make this disk.
    param([string] $Path, [hashtable] $Files)

    $null = New-VHD -Path $Path -SizeBytes 64MB -Dynamic
    $disk = Mount-VHD -Path $Path -Passthru | Get-Disk
    try {
        $volume = $disk | Initialize-Disk -PartitionStyle MBR -PassThru |
            New-Partition -UseMaximumSize -AssignDriveLetter |
            Format-Volume -FileSystem FAT32 -NewFileSystemLabel CIDATA -Confirm:$false
        foreach ($file in $Files.Keys) {
            Set-Content -LiteralPath "$($volume.DriveLetter):\$file" -Value $Files[$file] -Encoding utf8NoBOM
        }
    }
    finally {
        Dismount-VHD -Path $Path
    }
}

$config = Import-DeployConfig -Path $ConfigPath
$specs = $config.Vms
if ($Name) {
    $unknown = @($Name | Where-Object { $_ -notin $specs.Name })
    if ($unknown) { throw "Not in ${ConfigPath}: $($unknown -join ', ')" }
    $specs = @($specs | Where-Object Name -In $Name)
}

# Check the host before changing anything, so a typo stops the run instead of half of it.
if (-not (Get-VMSwitch | Where-Object Name -EQ $config.SwitchName)) { throw "Switch $($config.SwitchName) is not on this host." }
foreach ($spec in $specs) {
    $image = Join-Path -Path $config.ImageStore -ChildPath $spec.Image
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw "Image $image for VM $($spec.Name) does not exist." }
    if ($spec.OsDiskGB -and $spec.OsDiskGB * 1GB -lt (Get-VHD -Path $image).Size) {
        throw "VM $($spec.Name): OsDiskGB $($spec.OsDiskGB) is smaller than the image; a disk can only grow."
    }
    if ($spec.Os -eq 'windows' -and -not $LocalAdminCredential) { throw "VM $($spec.Name) is a Windows VM: pass -LocalAdminCredential." }
}

foreach ($spec in $specs) {
    $vm = Get-VM | Where-Object Name -EQ $spec.Name # Get-VM -Name would treat the name as a wildcard

    if (-not $vm) {
        $folder = Join-Path -Path $config.VmRoot -ChildPath $spec.Name
        if (Test-Path -LiteralPath $folder) { throw "$folder exists but VM $($spec.Name) does not. Look at it and remove it by hand." }
        if (-not $PSCmdlet.ShouldProcess($spec.Name, "Create a $($spec.Os) VM from $($spec.Image)")) { continue }

        $osDisk = Join-Path -Path $folder -ChildPath "$($spec.Name)-os.vhdx"
        $image = Join-Path -Path $config.ImageStore -ChildPath $spec.Image
        try {
            $null = New-Item -ItemType Directory -Path $folder
            if ($spec.Disk -eq 'Copy') {
                Copy-Item -LiteralPath $image -Destination $osDisk
                Set-ItemProperty -LiteralPath $osDisk -Name IsReadOnly -Value $false # the copy keeps the image's read-only flag
                if ($spec.OsDiskGB) { Resize-VHD -Path $osDisk -SizeBytes ($spec.OsDiskGB * 1GB) }
            }
            else {
                $null = New-VHD -Path $osDisk -ParentPath $image -Differencing
            }

            $seed = Get-SeedContent -Spec $spec -TimeZone $config.TimeZone -LocalAdminCredential $LocalAdminCredential
            $seedDisk = $null
            if ($spec.Os -eq 'windows') {
                Write-AnswerFile -DiskPath $osDisk -Content $seed['Unattend.xml']
            }
            else {
                $seedDisk = Join-Path -Path $folder -ChildPath "$($spec.Name)-seed.vhdx"
                Initialize-SeedDisk -Path $seedDisk -Files $seed
            }

            $vmArgs = @{
                Name               = $spec.Name
                Generation         = 2
                MemoryStartupBytes = $spec.MemoryGB * 1GB
                VHDPath            = $osDisk
                SwitchName         = $config.SwitchName
                Path               = $config.VmRoot
            }
            $vm = New-VM @vmArgs
            Set-VMProcessor -VM $vm -Count $spec.Cpus
            Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
            $template = if ($spec.Os -eq 'windows') { 'MicrosoftWindows' } else { 'MicrosoftUEFICertificateAuthority' }
            Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate $template -FirstBootDevice (Get-VMHardDiskDrive -VM $vm)
            if ($seedDisk) { Add-VMHardDiskDrive -VM $vm -Path $seedDisk }
            Set-VM -VM $vm -CheckpointType Disabled -AutomaticStartAction StartIfRunning -AutomaticStopAction ShutDown -Notes (ConvertTo-VMNote -Spec $spec)
            if ($spec.VlanId) { Set-VMNetworkAdapterVlan -VM $vm -Access -VlanId $spec.VlanId }
            if ($spec.Mac) { Set-VMNetworkAdapter -VM $vm -StaticMacAddress $spec.Mac }
            if ($spec.Tpm) {
                Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
                Enable-VMTPM -VM $vm
            }
            Start-VM -VM $vm
        }
        catch {
            # The folder did not exist before this run, so all of it is this run's half-made VM.
            # Removing it lets the next run start clean.
            $failure = $_
            $made = Get-VM | Where-Object Name -EQ $spec.Name
            if ($made) { Remove-VM -VM $made -Force }
            if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
            throw $failure
        }
        [pscustomobject]@{ VM = $spec.Name; Changed = $true; Actions = @('created') }
        continue
    }

    Assert-ManagedVM -VM $vm
    $adapter = @(Get-VMNetworkAdapter -VM $vm)
    if ($adapter.Count -ne 1) { throw "VM $($spec.Name) has $($adapter.Count) network adapters; this script manages VMs with one." }
    $driftArgs = @{
        Spec       = $spec
        VM         = $vm
        Adapter    = $adapter[0]
        Vlan       = Get-VMNetworkAdapterVlan -VMNetworkAdapter $adapter[0]
        TpmEnabled = (Get-VMSecurity -VM $vm).TpmEnabled
        SwitchName = $config.SwitchName
    }
    $drift = @(Get-VMDrift @driftArgs)
    if ($drift.Count -eq 0) {
        [pscustomobject]@{ VM = $spec.Name; Changed = $false; Actions = @() }
        continue
    }

    $refused = @($drift | Where-Object Kind -EQ 'Refuse')
    if ($refused) {
        $what = ($refused | ForEach-Object { "$($_.Setting) $($_.From) -> $($_.To)" }) -join ', '
        throw "VM $($spec.Name): $what cannot be changed in place. Remove the VM and deploy it again, or keep the old value."
    }
    $restart = [bool]($drift | Where-Object Kind -EQ 'Offline') -and $vm.State -ne 'Off'
    if ($restart -and -not $AllowRestart) {
        throw "VM $($spec.Name) is $($vm.State), and $(($drift | Where-Object Kind -EQ 'Offline').Setting -join ', ') can change only while it is off. Run again with -AllowRestart."
    }

    $actions = @($drift | ForEach-Object { "$($_.Setting) $($_.From) -> $($_.To)" })
    $plan = ($actions -join ', ') + $(if ($restart) { ' (restarts the VM)' } else { '' })
    if (-not $PSCmdlet.ShouldProcess($spec.Name, "Change $plan")) { continue }

    if ($restart) { Stop-VM -VM $vm -Force } # a shutdown through the guest; -Force only skips the prompt
    try {
        foreach ($change in $drift) {
            switch ($change.Setting) {
                'Cpus' { Set-VMProcessor -VM $vm -Count $spec.Cpus }
                'MemoryGB' { Set-VMMemory -VM $vm -StartupBytes ($spec.MemoryGB * 1GB) }
                'SwitchName' { Connect-VMNetworkAdapter -VMNetworkAdapter $adapter[0] -SwitchName $config.SwitchName }
                'VlanId' {
                    if ($spec.VlanId) { Set-VMNetworkAdapterVlan -VM $vm -Access -VlanId $spec.VlanId }
                    else { Set-VMNetworkAdapterVlan -VM $vm -Untagged }
                }
                'Mac' { Set-VMNetworkAdapter -VM $vm -StaticMacAddress $spec.Mac }
                'Tpm' {
                    # The TPM is off here, so a new key protector loses nothing the guest sealed.
                    Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
                    Enable-VMTPM -VM $vm
                }
            }
        }
    }
    finally {
        if ($restart) { Start-VM -VM $vm }
    }
    [pscustomobject]@{ VM = $spec.Name; Changed = $true; Actions = $actions }
}
