#Requires -Version 7.2
<#
.SYNOPSIS
Checks the PowerShell in evals/examples: PSScriptAnalyzer on the scripts, then the Pester tests.

.DESCRIPTION
evals/lint.sh runs this when pwsh is installed. Exits with 1 on a finding or a failed test.
Without PSScriptAnalyzer or Pester it prints a note and exits with 0, as the lint does for
other missing tools. Test files are not analyzed: their stand-in functions and mocks
break rules on purpose, and running them checks them.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$missing = @('PSScriptAnalyzer', 'Pester') | Where-Object { -not (Get-Module -ListAvailable -Name $_) }
if ($missing) {
    Write-Output "note: $($missing -join ' and ') not installed, PowerShell examples not checked"
    exit 0
}

$examples = Join-Path -Path $PSScriptRoot -ChildPath 'examples'
$failed = $false

$scripts = Get-ChildItem -Path $examples -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
    Where-Object Name -NotLike '*.Tests.ps1'
$findings = @($scripts | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Warning, Error })
if ($findings.Count -gt 0) {
    $findings | Format-Table -Property ScriptName, Line, RuleName, Message -AutoSize -Wrap | Out-String -Width 160 | Write-Output
    Write-Output "FAIL: PSScriptAnalyzer found $($findings.Count) problems"
    $failed = $true
}

if (Get-ChildItem -Path $examples -Recurse -Filter '*.Tests.ps1') {
    $result = Invoke-Pester -Path $examples -PassThru -Output None
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        $result.Failed | ForEach-Object { Write-Output "FAIL: $($_.ExpandedPath): $($_.ErrorRecord)" }
        Write-Output "FAIL: Pester: $($result.FailedCount) failed"
        $failed = $true
    }
}

if ($failed) { exit 1 }
