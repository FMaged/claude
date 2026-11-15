BeforeAll {
    # Pester can mock only commands that exist. On a machine without Hyper-V, this
    # stand-in module gives the names, and #Requires -Modules Hyper-V finds it loaded.
    New-Module -Name Hyper-V -ScriptBlock {
        function Get-VM { }
        function Get-VMSecurity { param($VM) }
        function Set-VMKeyProtector { param($VM, [switch] $NewLocalKeyProtector) }
        function Enable-VMTPM { param($VM) }
        function Stop-VM { param($VM) }
        function Start-VM { param($VM) }
    } | Import-Module

    $script = Join-Path $PSScriptRoot 'Add-VMVirtualTpm.ps1'

    function Set-TestVM {
        param([string] $State = 'Off', [int] $Generation = 2, [bool] $TpmEnabled = $false)
        $vm = [pscustomobject]@{ Name = 'web01'; State = $State; Generation = $Generation }
        Mock Get-VM { $vm }.GetNewClosure()
        Mock Get-VMSecurity { [pscustomobject]@{ TpmEnabled = $TpmEnabled } }.GetNewClosure()
    }
}

Describe 'Add-VMVirtualTpm' {
    BeforeEach {
        Mock Set-VMKeyProtector { }
        Mock Enable-VMTPM { }
        Mock Stop-VM { }
        Mock Start-VM { }
    }

    It 'leaves a VM whose TPM is on alone' {
        Set-TestVM -TpmEnabled $true
        $result = & $script -Name web01
        $result.Changed | Should -BeFalse
        Should -Invoke Set-VMKeyProtector -Times 0 -Exactly
        Should -Invoke Enable-VMTPM -Times 0 -Exactly
    }

    It 'turns the TPM on for a VM that is off, without a restart' {
        Set-TestVM
        $result = & $script -Name web01
        $result.Changed | Should -BeTrue
        Should -Invoke Set-VMKeyProtector -Times 1 -Exactly
        Should -Invoke Enable-VMTPM -Times 1 -Exactly
        Should -Invoke Stop-VM -Times 0 -Exactly
        Should -Invoke Start-VM -Times 0 -Exactly
    }

    It 'changes nothing under -WhatIf' {
        Set-TestVM -State 'Running'
        & $script -Name web01 -AllowRestart -WhatIf | Should -BeNullOrEmpty
        foreach ($command in 'Set-VMKeyProtector', 'Enable-VMTPM', 'Stop-VM', 'Start-VM') {
            Should -Invoke $command -Times 0 -Exactly
        }
    }

    It 'stops at a running VM without -AllowRestart' {
        Set-TestVM -State 'Running'
        { & $script -Name web01 } | Should -Throw '*only while it is off*'
        Should -Invoke Stop-VM -Times 0 -Exactly
        Should -Invoke Enable-VMTPM -Times 0 -Exactly
    }

    It 'restarts a running VM with -AllowRestart' {
        Set-TestVM -State 'Running'
        & $script -Name web01 -AllowRestart | Out-Null
        Should -Invoke Stop-VM -Times 1 -Exactly
        Should -Invoke Enable-VMTPM -Times 1 -Exactly
        Should -Invoke Start-VM -Times 1 -Exactly
    }

    It 'starts the VM again when turning the TPM on fails' {
        Set-TestVM -State 'Running'
        Mock Enable-VMTPM { throw 'host refused' }
        { & $script -Name web01 -AllowRestart } | Should -Throw 'host refused'
        Should -Invoke Start-VM -Times 1 -Exactly
    }

    It 'refuses a generation 1 VM' {
        Set-TestVM -Generation 1
        { & $script -Name web01 } | Should -Throw '*generation 1*'
    }

    It 'stops when the VM does not exist' {
        Mock Get-VM { }
        { & $script -Name web01 } | Should -Throw '*does not exist*'
    }
}
