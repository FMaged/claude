@{
    RootModule        = 'HyperVDeploy.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '3d5e1f7a-8c2b-4f6e-9a1d-5b7c2e4f8a90'
    Author            = 'hyperv-deploy example'
    Description       = 'Config, drift, and first-boot logic shared by Deploy-HyperVVM.ps1 and Remove-HyperVVM.ps1.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @('Import-DeployConfig', 'ConvertTo-VMNote', 'ConvertFrom-VMNote', 'Assert-ManagedVM', 'Get-VMDrift', 'Get-SeedContent')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
