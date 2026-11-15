# The logic Deploy-HyperVVM.ps1 and Remove-HyperVVM.ps1 share. Nothing here changes the host.
Set-StrictMode -Version Latest

$Owner = 'hyperv-deploy'
$TopKeys = 'VmRoot', 'ImageStore', 'SwitchName', 'TimeZone', 'Vms'
$VmDefaults = [ordered]@{
    Image    = $null
    Os       = $null
    SshKey   = $null
    Cpus     = 2
    MemoryGB = 4
    Disk     = 'Copy'
    OsDiskGB = $null
    VlanId   = $null
    Mac      = $null
    Tpm      = $false
}

function Import-DeployConfig {
    <#
    .SYNOPSIS
    Reads an environment's data file and checks every value before anything changes.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $data = Import-PowerShellDataFile -LiteralPath $Path
    $problems = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $data.Keys) {
        if ($key -notin $TopKeys) { $problems.Add("unknown setting '$key'") }
    }
    foreach ($key in $TopKeys) {
        if (-not $data.ContainsKey($key)) { $problems.Add("missing setting '$key'") }
    }
    foreach ($key in 'VmRoot', 'ImageStore') {
        if ($data.ContainsKey($key) -and $data[$key] -notmatch '^[A-Za-z]:\\') {
            $problems.Add("$key must be an absolute Windows path, for example D:\VMs")
        }
    }
    $vmTable = if ($data['Vms'] -is [hashtable]) { $data['Vms'] } else { @{} }

    $specs = foreach ($name in @($vmTable.Keys | Sort-Object)) {
        $where = "VM '$name'"
        $vm = $vmTable[$name]
        if ($name -cnotmatch '^[a-z][a-z0-9-]{0,14}$') {
            $problems.Add("${where}: the name must be lowercase, start with a letter, and be at most 15 characters")
        }
        if ($vm -isnot [hashtable]) {
            $problems.Add("${where}: must be a @{ } table")
            continue
        }
        foreach ($key in $vm.Keys) {
            # Terraform drops a misspelled optional attribute and takes the default; this stops.
            if (-not $VmDefaults.Contains($key)) { $problems.Add("${where}: unknown setting '$key'") }
        }

        $spec = [ordered]@{ Name = $name }
        foreach ($key in $VmDefaults.Keys) {
            $spec[$key] = if ($vm.ContainsKey($key)) { $vm[$key] } else { $VmDefaults[$key] }
        }
        $spec = [pscustomobject]$spec

        if ($spec.Image -notmatch '^[A-Za-z0-9._-]+\.vhdx$') { $problems.Add("${where}: Image must be a .vhdx file name, without a folder") }
        if ($spec.Os -cnotin 'windows', 'linux') { $problems.Add("${where}: Os must be 'windows' or 'linux'") }
        if ($spec.Cpus -isnot [int] -or $spec.Cpus -lt 1 -or $spec.Cpus -gt 64) { $problems.Add("${where}: Cpus must be a whole number from 1 to 64") }
        if ($spec.MemoryGB -isnot [int] -or $spec.MemoryGB -lt 1 -or $spec.MemoryGB -gt 1024) { $problems.Add("${where}: MemoryGB must be a whole number from 1 to 1024") }
        if ($spec.Disk -cnotin 'Copy', 'Differencing') { $problems.Add("${where}: Disk must be 'Copy' or 'Differencing'") }
        if ($null -ne $spec.OsDiskGB) {
            if ($spec.Disk -ne 'Copy') { $problems.Add("${where}: OsDiskGB works only with Disk = 'Copy'; a differencing disk is as big as its image") }
            elseif ($spec.OsDiskGB -isnot [int] -or $spec.OsDiskGB -lt 1) { $problems.Add("${where}: OsDiskGB must be a whole number of GB") }
        }
        if ($null -ne $spec.VlanId -and ($spec.VlanId -isnot [int] -or $spec.VlanId -lt 1 -or $spec.VlanId -gt 4094)) { $problems.Add("${where}: VlanId must be from 1 to 4094") }
        if ($null -ne $spec.Mac -and $spec.Mac -cnotmatch '^[0-9A-F]{12}$') { $problems.Add("${where}: Mac must be 12 upper-case hex digits, as Hyper-V shows it") }
        if ($spec.Tpm -isnot [bool]) { $problems.Add("${where}: Tpm must be `$true or `$false") }
        if ($spec.Os -eq 'linux' -and [string]::IsNullOrWhiteSpace($spec.SshKey)) { $problems.Add("${where}: a Linux VM needs SshKey, the public key cloud-init installs") }
        if ($spec.Os -eq 'windows' -and $null -ne $spec.SshKey) { $problems.Add("${where}: SshKey is only for Linux VMs") }
        $spec
    }

    if ($problems.Count -gt 0) { throw "$Path has problems:`n  $($problems -join "`n  ")" }
    [pscustomobject]@{
        VmRoot     = $data.VmRoot
        ImageStore = $data.ImageStore
        SwitchName = $data.SwitchName
        TimeZone   = $data.TimeZone
        Vms        = @($specs)
    }
}

function ConvertTo-VMNote {
    <#
    .SYNOPSIS
    The VM's notes: who owns it, and the settings that are fixed once it exists.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Spec)

    @("Managed-by: $Owner", "Image: $($Spec.Image)", "Disk: $($Spec.Disk)", "OsDiskGB: $($Spec.OsDiskGB)") -join "`n"
}

function ConvertFrom-VMNote {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyString()] [string] $Notes)

    $note = @{}
    foreach ($line in $Notes -split "`r?`n") {
        if ($line -match '^([A-Za-z-]+): ?(.*)$') { $note[$Matches[1]] = $Matches[2] }
    }
    $note
}

function Assert-ManagedVM {
    <#
    .SYNOPSIS
    Stops unless the VM's notes say this script owns it. One owner per VM: Terraform, a person, or this.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $VM)

    if ((ConvertFrom-VMNote $VM.Notes)['Managed-by'] -ne $Owner) {
        throw "VM $($VM.Name) is not managed by $Owner (its notes do not say so). Leave it to its owner."
    }
}

function Get-VMDrift {
    <#
    .SYNOPSIS
    Compares a VM on the host with its spec and returns one object per difference.

    .DESCRIPTION
    Kind is Online (applied while the VM runs), Offline (needs the VM off), or Refuse
    (the script will not do it; the message says what to do instead).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Spec,
        [Parameter(Mandatory)] $VM,
        [Parameter(Mandatory)] $Adapter,
        [Parameter(Mandatory)] $Vlan,
        [Parameter(Mandatory)] [bool] $TpmEnabled,
        [Parameter(Mandatory)] [string] $SwitchName
    )

    $drift = [System.Collections.Generic.List[object]]::new()
    $add = { param($Setting, $From, $To, $Kind) $drift.Add([pscustomobject]@{ Setting = $Setting; From = $From; To = $To; Kind = $Kind }) }

    $note = ConvertFrom-VMNote $VM.Notes
    foreach ($key in 'Image', 'Disk', 'OsDiskGB') {
        $now = if ($note.ContainsKey($key)) { $note[$key] } else { '' }
        if ($now -ne "$($Spec.$key)") { & $add $key $now $Spec.$key 'Refuse' }
    }
    if ($VM.ProcessorCount -ne $Spec.Cpus) { & $add 'Cpus' $VM.ProcessorCount $Spec.Cpus 'Offline' }
    if ($VM.MemoryStartup -ne $Spec.MemoryGB * 1GB) { & $add 'MemoryGB' ($VM.MemoryStartup / 1GB) $Spec.MemoryGB 'Offline' }
    if ($Adapter.SwitchName -ne $SwitchName) { & $add 'SwitchName' $Adapter.SwitchName $SwitchName 'Online' }
    $vlanNow = if ($Vlan.OperationMode -eq 'Access') { $Vlan.AccessVlanId } else { $null }
    if ($vlanNow -ne $Spec.VlanId) { & $add 'VlanId' $vlanNow $Spec.VlanId 'Online' }
    if ($null -ne $Spec.Mac -and $Adapter.MacAddress -ne $Spec.Mac) { & $add 'Mac' $Adapter.MacAddress $Spec.Mac 'Offline' }
    if ($Spec.Tpm -and -not $TpmEnabled) { & $add 'Tpm' $false $true 'Offline' }
    if (-not $Spec.Tpm -and $TpmEnabled) { & $add 'Tpm' $true $false 'Refuse' }
    $drift
}

function Get-SeedContent {
    <#
    .SYNOPSIS
    The first-boot files for a VM, the same content Terraform's seed carries.

    .DESCRIPTION
    Windows: Unattend.xml, which the deploy script writes into the OS disk's Panther folder.
    Linux: meta-data and user-data for cloud-init's NoCloud source, written as JSON (which
    is YAML), so no value needs YAML quoting.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Spec,
        [Parameter(Mandatory)] [string] $TimeZone,
        [pscredential] $LocalAdminCredential
    )

    if ($Spec.Os -eq 'linux') {
        return @{
            'meta-data' = [ordered]@{ 'instance-id' = "$($Spec.Name)-$($Spec.Image)"; 'local-hostname' = $Spec.Name } | ConvertTo-Json
            'user-data' = "#cloud-config`n" + ([ordered]@{ hostname = $Spec.Name; ssh_authorized_keys = @($Spec.SshKey) } | ConvertTo-Json)
        }
    }

    if (-not $LocalAdminCredential) { throw "VM $($Spec.Name) is a Windows VM and needs -LocalAdminCredential." }
    $computerName = [Security.SecurityElement]::Escape($Spec.Name.ToUpperInvariant())
    $zone = [Security.SecurityElement]::Escape($TimeZone)
    $password = [Security.SecurityElement]::Escape($LocalAdminCredential.GetNetworkCredential().Password)
    $shell = 'name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"'
    @{
        'Unattend.xml' = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component $shell>
      <ComputerName>$computerName</ComputerName>
      <TimeZone>$zone</TimeZone>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component $shell>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>$password</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
    </component>
  </settings>
</unattend>
"@
    }
}

Export-ModuleMember -Function Import-DeployConfig, ConvertTo-VMNote, ConvertFrom-VMNote, Assert-ManagedVM, Get-VMDrift, Get-SeedContent
