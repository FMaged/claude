#Requires -Version 5.1
# Removes what the build leaves behind, so every clone starts clean and the copy is small.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The answer file's one auto logon. Setup turns it off after the logon but can leave the values.
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$present = (Get-ItemProperty -Path $winlogon).PSObject.Properties.Name
foreach ($name in 'AutoAdminLogon', 'DefaultPassword', 'AutoLogonCount') {
    if ($present -contains $name) {
        Remove-ItemProperty -Path $winlogon -Name $name
    }
}

# The downloaded update packages are installed by now; they only make every copy bigger.
Stop-Service -Name wuauserv -Force
Get-ChildItem -LiteralPath "$env:SystemRoot\SoftwareDistribution\Download" -Force | Remove-Item -Recurse -Force
Start-Service -Name wuauserv

# Superseded component versions. The windows-restart after this script finishes the job.
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet
if ($LASTEXITCODE -notin 0, 3010) { throw "DISM component clean up failed with exit code $LASTEXITCODE" }
