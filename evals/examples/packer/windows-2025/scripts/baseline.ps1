#Requires -Version 5.1
# Settings every VM made from this image needs. Per-host and per-app settings belong to Ansible.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# High performance: a power-saving plan only slows a VM down.
powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive failed with exit code $LASTEXITCODE" }

powercfg.exe /hibernate off
if ($LASTEXITCODE -ne 0) { throw "powercfg /hibernate failed with exit code $LASTEXITCODE" }

# These servers print nothing, and the spooler is a frequent attack path.
Stop-Service -Name Spooler -Force
Set-Service -Name Spooler -StartupType Disabled
