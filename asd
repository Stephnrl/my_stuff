@{
    RootModule        = 'AAP.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Platform Engineering'
    CompanyName       = 'YourOrg'
    Copyright         = '(c) YourOrg. All rights reserved.'
    Description       = 'PowerShell module for interacting with Red Hat Ansible Automation Platform 2.5 controller API.'

    # Pin to PS 7.x — the GHA composite action runs pwsh, not Windows PowerShell.
    # Some of what we use (ConvertFrom-Json -AsHashtable, ternary operator) is 7+ only.
    PowerShellVersion = '7.2'

    FunctionsToExport = @(
        'Connect-AAPController'
        'Invoke-AAPJobTemplate'
        'Get-AAPJob'
        'Get-AAPJobStdout'
        'Stop-AAPJob'
        'Wait-AAPJob'
        'Resolve-AAPJobTemplate'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('AAP', 'Ansible', 'Automation', 'RedHat')
            ProjectUri   = 'https://github.com/your-org/gha-actions'
            ReleaseNotes = 'Initial release.'
        }
    }
}
