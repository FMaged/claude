BeforeAll {
    # Pester can mock only commands that exist. On a machine without Hyper-V, these stand-in
    # modules give the names, and #Requires -Modules Hyper-V finds one loaded.
    New-Module -Name Hyper-V -ScriptBlock {
        function Get-VM { }
        function Get-VMSwitch { }
        function Get-VHD { param($Path) }
        function New-VHD { param($Path, $SizeBytes, [switch] $Dynamic, $ParentPath, [switch] $Differencing) }
        function Resize-VHD { param($Path, $SizeBytes) }
        function Mount-VHD { param($Path, [switch] $Passthru) }
        function Dismount-VHD { param($Path) }
        function New-VM { param($Name, $Generation, $MemoryStartupBytes, $VHDPath, $SwitchName, $Path) }
        function Set-VM { param($VM, $CheckpointType, $AutomaticStartAction, $AutomaticStopAction, $Notes) }
        function Set-VMProcessor { param($VM, $Count) }
        function Set-VMMemory { param($VM, $DynamicMemoryEnabled, $StartupBytes) }
        function Set-VMFirmware { param($VM, $EnableSecureBoot, $SecureBootTemplate, $FirstBootDevice) }
        function Get-VMHardDiskDrive { param($VM) }
        function Add-VMHardDiskDrive { param($VM, $Path) }
        function Get-VMNetworkAdapter { param($VM) }
        function Set-VMNetworkAdapter { param($VM, $StaticMacAddress) }
        function Connect-VMNetworkAdapter { param($VMNetworkAdapter, $SwitchName) }
        function Get-VMNetworkAdapterVlan { param($VMNetworkAdapter) }
        function Set-VMNetworkAdapterVlan { param($VM, [switch] $Access, $VlanId, [switch] $Untagged) }
        function Get-VMSecurity { param($VM) }
        function Set-VMKeyProtector { param($VM, [switch] $NewLocalKeyProtector) }
        function Enable-VMTPM { param($VM) }
        function Start-VM { param($VM) }
        function Stop-VM { param($VM, [switch] $Force, [switch] $TurnOff) }
        function Remove-VM { param($VM, [switch] $Force) }
    } | Import-Module
    New-Module -Name Storage -ScriptBlock {
        function Get-Disk { param([Parameter(ValueFromPipeline)] $InputObject) }
        function Initialize-Disk { param([Parameter(ValueFromPipeline)] $InputObject, $PartitionStyle, [switch] $PassThru) }
        function New-Partition { param([Parameter(ValueFromPipeline)] $InputObject, [switch] $UseMaximumSize, [switch] $AssignDriveLetter) }
        function Format-Volume { [CmdletBinding(SupportsShouldProcess)] param([Parameter(ValueFromPipeline)] $InputObject, $FileSystem, $NewFileSystemLabel) }
        function Get-Partition { param($DiskNumber, $PartitionNumber) }
        function Get-PartitionSupportedSize { param($DiskNumber, $PartitionNumber) }
        function Resize-Partition { param($DiskNumber, $PartitionNumber, $Size) }
        function Add-PartitionAccessPath { param($DiskNumber, $PartitionNumber, [switch] $AssignDriveLetter) }
    } | Import-Module
    Import-Module (Join-Path $PSScriptRoot 'HyperVDeploy.psd1') -Force

    # Join-Path, and Set-Content's -Encoding, need the drive in a path to exist: D: for the
    # data file's paths, F: and G: for the drive letters the mocked disks get.
    foreach ($letter in 'D', 'F', 'G') {
        if (-not (Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction Ignore)) {
            $null = New-PSDrive -Name $letter -PSProvider FileSystem -Root ([IO.Path]::GetTempPath()) -Scope Global
        }
    }

    $deploy = Join-Path $PSScriptRoot 'Deploy-HyperVVM.ps1'
    $remove = Join-Path $PSScriptRoot 'Remove-HyperVVM.ps1'
    $configPath = Join-Path $PSScriptRoot 'envs/lab.psd1'
    $credential = [pscredential]::new('Administrator', (ConvertTo-SecureString 'Lab&Pass<1' -AsPlainText -Force))
    $changing = @(
        'New-Item', 'Copy-Item', 'Set-ItemProperty', 'Set-Content', 'Remove-Item',
        'New-VHD', 'Resize-VHD', 'Mount-VHD', 'Resize-Partition', 'Add-PartitionAccessPath', 'Initialize-Disk',
        'New-VM', 'Set-VM', 'Set-VMProcessor', 'Set-VMMemory', 'Set-VMFirmware', 'Add-VMHardDiskDrive',
        'Set-VMNetworkAdapter', 'Connect-VMNetworkAdapter', 'Set-VMNetworkAdapterVlan',
        'Set-VMKeyProtector', 'Enable-VMTPM', 'Start-VM', 'Stop-VM', 'Remove-VM'
    )

    # A VM on the host exactly as the data file describes it.
    function Get-MatchingVM {
        param([string] $VmName, [string] $State = 'Running')
        $spec = (Import-DeployConfig -Path $configPath).Vms | Where-Object Name -EQ $VmName
        [pscustomobject]@{
            Name           = $spec.Name
            State          = $State
            Generation     = 2
            ProcessorCount = $spec.Cpus
            MemoryStartup  = $spec.MemoryGB * 1GB
            Notes          = ConvertTo-VMNote -Spec $spec
        }
    }

    function New-TestConfig {
        param([string] $VmBody)
        $path = Join-Path $TestDrive "$([guid]::NewGuid()).psd1"
        Set-Content -LiteralPath $path -Value "@{ VmRoot = 'D:\VMs'; ImageStore = 'D:\Images'; SwitchName = 'LAN'; TimeZone = 'UTC'; Vms = @{ 'vm1' = @{ $VmBody } } }"
        $path
    }
}

Describe 'Import-DeployConfig' {
    It 'loads the lab file and fills in the defaults' {
        $config = Import-DeployConfig -Path $configPath
        $db = $config.Vms | Where-Object Name -EQ 'lab-db01'
        $db.Cpus | Should -Be 2
        $db.MemoryGB | Should -Be 4
        $db.Tpm | Should -BeFalse
        ($config.Vms | Where-Object Name -EQ 'lab-web01').Cpus | Should -Be 4
    }

    It 'stops at <Case>' -ForEach @(
        @{ Case = 'a misspelled setting, which Terraform would drop'; Body = "Image = 'a.vhdx'; Os = 'linux'; SshKey = 'k'; Cpu = 4"; Message = "*unknown setting 'Cpu'*" }
        @{ Case = 'OsDiskGB on a differencing disk'; Body = "Image = 'a.vhdx'; Os = 'linux'; SshKey = 'k'; Disk = 'Differencing'; OsDiskGB = 80"; Message = '*OsDiskGB works only*' }
        @{ Case = 'a Linux VM without a key'; Body = "Image = 'a.vhdx'; Os = 'linux'"; Message = '*needs SshKey*' }
        @{ Case = 'an image with a folder'; Body = "Image = 'D:\a.vhdx'; Os = 'windows'"; Message = '*without a folder*' }
        @{ Case = 'Os in the wrong case'; Body = "Image = 'a.vhdx'; Os = 'Windows'"; Message = "*Os must be*" }
    ) {
        { Import-DeployConfig -Path (New-TestConfig $Body) } | Should -Throw $Message
    }
}

Describe 'Get-SeedContent' {
    It 'escapes the password in the Windows answer file' {
        $spec = (Import-DeployConfig -Path $configPath).Vms | Where-Object Name -EQ 'lab-web01'
        $xml = [xml] (Get-SeedContent -Spec $spec -TimeZone 'UTC' -LocalAdminCredential $credential)['Unattend.xml']
        $pass = @{}
        foreach ($settings in $xml.unattend.settings) { $pass[$settings.pass] = $settings.component }
        $pass['specialize'].ComputerName | Should -Be 'LAB-WEB01'
        $pass['oobeSystem'].UserAccounts.AdministratorPassword.Value | Should -Be 'Lab&Pass<1'
    }

    It 'writes cloud-init files that parse' {
        $spec = (Import-DeployConfig -Path $configPath).Vms | Where-Object Name -EQ 'lab-db01'
        $seed = Get-SeedContent -Spec $spec -TimeZone 'UTC'
        $seed['user-data'] | Should -BeLike "#cloud-config`n*"
        ($seed['user-data'] -replace '^#cloud-config\n' | ConvertFrom-Json).ssh_authorized_keys | Should -Be $spec.SshKey
        ($seed['meta-data'] | ConvertFrom-Json).'instance-id' | Should -Be 'lab-db01-debian13-20261115-a1b2c3d.vhdx'
    }
}

Describe 'Get-VMDrift' {
    BeforeAll {
        $spec = (Import-DeployConfig -Path $configPath).Vms | Where-Object Name -EQ 'lab-web01'
        $adapter = [pscustomobject]@{ SwitchName = 'LAN'; MacAddress = '00155D010203' }
    }

    It 'finds nothing on a VM that matches' {
        $vlan = [pscustomobject]@{ OperationMode = 'Access'; AccessVlanId = 20 }
        Get-VMDrift -Spec $spec -VM (Get-MatchingVM 'lab-web01') -Adapter $adapter -Vlan $vlan -TpmEnabled $true -SwitchName 'LAN' |
            Should -BeNullOrEmpty
    }

    It 'sorts each difference by what it needs' {
        $vm = Get-MatchingVM 'lab-web01'
        $vm.ProcessorCount = 2
        $vm.Notes = $vm.Notes -replace 'Image: .*', 'Image: win2025-20261001-0000000.vhdx'
        $vlan = [pscustomobject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
        $drift = Get-VMDrift -Spec $spec -VM $vm -Adapter $adapter -Vlan $vlan -TpmEnabled $false -SwitchName 'LAN'
        ($drift | Where-Object Setting -EQ 'Cpus').Kind | Should -Be 'Offline'
        ($drift | Where-Object Setting -EQ 'VlanId').Kind | Should -Be 'Online'
        ($drift | Where-Object Setting -EQ 'Image').Kind | Should -Be 'Refuse'
        ($drift | Where-Object Setting -EQ 'Tpm').Kind | Should -Be 'Offline'
    }
}

Describe 'Deploy-HyperVVM' {
    BeforeEach {
        foreach ($command in $changing) { Mock $command { } }
        Mock Get-VM { }
        Mock Get-VMSwitch { [pscustomobject]@{ Name = 'LAN' } }
        # Any other path, such as the data file, is checked for real. Not with Test-Path itself:
        # Pester mocks the module-qualified name too, and the mock would call itself.
        Mock Test-Path { [IO.File]::Exists($LiteralPath) }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'D:?Images*' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like 'D:?VMs*' }
        Mock Get-VHD { [pscustomobject]@{ Size = 40GB } }
        Mock New-VM { [pscustomobject]@{ Name = $Name } }
        Mock Mount-VHD { [pscustomobject]@{ Path = $Path } }
        Mock Get-Disk { [pscustomobject]@{ Number = 3 } }
        Mock Get-Partition { [pscustomobject]@{ PartitionNumber = 3; GptType = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'; Size = 40GB; DriveLetter = 'F' } }
        Mock Get-PartitionSupportedSize { [pscustomobject]@{ SizeMax = 80GB } }
        Mock Initialize-Disk { [pscustomobject]@{ Number = 4 } }
        Mock New-Partition { [pscustomobject]@{ PartitionNumber = 1 } }
        Mock Format-Volume { [pscustomobject]@{ DriveLetter = 'G' } }
        Mock Get-VMHardDiskDrive { [pscustomobject]@{ Path = 'os.vhdx' } }
        Mock Get-VMNetworkAdapter { [pscustomobject]@{ VMName = $VM.Name; SwitchName = 'LAN'; MacAddress = '00155D010203' } }
        Mock Get-VMNetworkAdapterVlan {
            if ($VMNetworkAdapter.VMName -eq 'lab-web01') { [pscustomobject]@{ OperationMode = 'Access'; AccessVlanId = 20 } }
            else { [pscustomobject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 } }
        }
        Mock Get-VMSecurity { [pscustomobject]@{ TpmEnabled = $VM.Name -eq 'lab-web01' } }
    }

    It 'creates both VMs on an empty host' {
        $result = & $deploy -ConfigPath $configPath -LocalAdminCredential $credential
        $result.Changed | Should -Be @($true, $true)
        Should -Invoke New-VM -Times 2 -Exactly
        Should -Invoke Copy-Item -Times 1 -Exactly                      # lab-web01 is a copy
        Should -Invoke Resize-VHD -Times 1 -Exactly
        Should -Invoke New-VHD -Times 1 -Exactly -ParameterFilter { $Differencing } # lab-db01
        Should -Invoke Set-Content -Times 1 -Exactly -ParameterFilter { $LiteralPath -like '*Panther*Unattend.xml' }
        Should -Invoke Set-Content -Times 2 -Exactly -ParameterFilter { $LiteralPath -like 'G:*' } # the CIDATA disk
        Should -Invoke Enable-VMTPM -Times 1 -Exactly
        Should -Invoke Start-VM -Times 2 -Exactly
    }

    It 'changes nothing under -WhatIf' {
        & $deploy -ConfigPath $configPath -LocalAdminCredential $credential -WhatIf | Should -BeNullOrEmpty
        foreach ($command in $changing) { Should -Invoke $command -Times 0 -Exactly }
    }

    It 'changes nothing on a second run' {
        Mock Get-VM { Get-MatchingVM 'lab-web01'; Get-MatchingVM 'lab-db01' }
        $result = & $deploy -ConfigPath $configPath -LocalAdminCredential $credential
        $result.Changed | Should -Be @($false, $false)
        foreach ($command in $changing) { Should -Invoke $command -Times 0 -Exactly }
    }

    It 'stops before changing anything when an image is missing' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like 'D:?Images*' }
        { & $deploy -ConfigPath $configPath -LocalAdminCredential $credential } | Should -Throw '*does not exist*'
        foreach ($command in $changing) { Should -Invoke $command -Times 0 -Exactly }
    }

    It 'needs -AllowRestart for a change that needs the VM off' {
        Mock Get-VM { $vm = Get-MatchingVM 'lab-web01'; $vm.ProcessorCount = 2; $vm }
        { & $deploy -ConfigPath $configPath -Name lab-web01 -LocalAdminCredential $credential } | Should -Throw '*-AllowRestart*'
        Should -Invoke Set-VMProcessor -Times 0 -Exactly
    }

    It 'restarts the VM with -AllowRestart' {
        Mock Get-VM { $vm = Get-MatchingVM 'lab-web01'; $vm.ProcessorCount = 2; $vm }
        $result = & $deploy -ConfigPath $configPath -Name lab-web01 -LocalAdminCredential $credential -AllowRestart
        $result.Actions | Should -Be @('Cpus 2 -> 4')
        Should -Invoke Stop-VM -Times 1 -Exactly
        Should -Invoke Set-VMProcessor -Times 1 -Exactly
        Should -Invoke Start-VM -Times 1 -Exactly
    }

    It 'refuses a VM it did not make' {
        Mock Get-VM { $vm = Get-MatchingVM 'lab-web01'; $vm.Notes = ''; $vm }
        { & $deploy -ConfigPath $configPath -Name lab-web01 -LocalAdminCredential $credential } | Should -Throw '*not managed by hyperv-deploy*'
    }

    It 'refuses an image change in place' {
        Mock Get-VM { $vm = Get-MatchingVM 'lab-web01'; $vm.Notes = $vm.Notes -replace 'Image: .*', 'Image: old.vhdx'; $vm }
        { & $deploy -ConfigPath $configPath -Name lab-web01 -LocalAdminCredential $credential } | Should -Throw '*cannot be changed in place*'
        foreach ($command in $changing) { Should -Invoke $command -Times 0 -Exactly }
    }

    It 'removes a half-made VM when creating it fails' {
        # A table, because a mock body runs in another scope and sees changes to it only by reference.
        $made = @{ Folder = $false; VM = $false }
        Mock New-Item { $made.Folder = $true }.GetNewClosure()
        Mock Test-Path { $made.Folder }.GetNewClosure() -ParameterFilter { $LiteralPath -like 'D:?VMs*' }
        Mock New-VM { $made.VM = $true; [pscustomobject]@{ Name = $Name } }.GetNewClosure()
        Mock Get-VM { if ($made.VM) { [pscustomobject]@{ Name = 'lab-db01' } } }.GetNewClosure()
        Mock Set-VMFirmware { throw 'firmware refused' }
        { & $deploy -ConfigPath $configPath -Name lab-db01 } | Should -Throw 'firmware refused'
        Should -Invoke Remove-VM -Times 1 -Exactly
        Should -Invoke Remove-Item -Times 1 -Exactly
        Should -Invoke Start-VM -Times 0 -Exactly
    }
}

Describe 'Remove-HyperVVM' {
    BeforeAll {
        $folder = Join-Path 'D:\VMs' 'lab-db01'
    }

    BeforeEach {
        foreach ($command in $changing) { Mock $command { } }
        Mock Get-VM { Get-MatchingVM 'lab-db01' }
        Mock Get-VMHardDiskDrive { [pscustomobject]@{ Path = "$folder\lab-db01-os.vhdx" }; [pscustomobject]@{ Path = "$folder\lab-db01-seed.vhdx" } }
    }

    It 'deletes only the VM and its own folder' {
        $result = & $remove -ConfigPath $configPath -Name lab-db01 -Confirm:$false
        $result.Changed | Should -BeTrue
        Should -Invoke Stop-VM -Times 1 -Exactly
        Should -Invoke Remove-VM -Times 1 -Exactly
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $folder }
    }

    It 'changes nothing under -WhatIf' {
        & $remove -ConfigPath $configPath -Name lab-db01 -WhatIf | Should -BeNullOrEmpty
        foreach ($command in $changing) { Should -Invoke $command -Times 0 -Exactly }
    }

    It 'refuses a VM with a disk outside its folder' {
        Mock Get-VMHardDiskDrive { [pscustomobject]@{ Path = 'E:\Data\shared.vhdx' } }
        { & $remove -ConfigPath $configPath -Name lab-db01 -Confirm:$false } | Should -Throw '*outside*'
        Should -Invoke Remove-VM -Times 0 -Exactly
    }

    It 'refuses a VM it did not make' {
        Mock Get-VM { $vm = Get-MatchingVM 'lab-db01'; $vm.Notes = 'Managed-by: terraform'; $vm }
        { & $remove -ConfigPath $configPath -Name lab-db01 -Confirm:$false } | Should -Throw '*not managed by hyperv-deploy*'
        Should -Invoke Remove-VM -Times 0 -Exactly
    }

    It 'reports a VM that is not there' {
        Mock Get-VM { }
        (& $remove -ConfigPath $configPath -Name lab-db01 -Confirm:$false).Changed | Should -BeFalse
    }
}
