# Lab VMs on the Hyper-V host. ./Deploy-HyperVVM.ps1 -ConfigPath envs/lab.psd1 -WhatIf shows what would change.
@{
    VmRoot     = 'D:\VMs'
    ImageStore = 'D:\Images'
    SwitchName = 'LAN'
    TimeZone   = 'W. Europe Standard Time'
    Vms        = @{
        'lab-web01' = @{
            Image    = 'win2025-20261115-a1b2c3d.vhdx'
            Os       = 'windows'
            Cpus     = 4
            MemoryGB = 8
            OsDiskGB = 80
            VlanId   = 20
            Tpm      = $true
        }
        'lab-db01'  = @{
            Image  = 'debian13-20261115-a1b2c3d.vhdx'
            Os     = 'linux'
            Disk   = 'Differencing'
            SshKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderPublicKeyForTheExampleOnly000 admin@lab'
        }
    }
}
