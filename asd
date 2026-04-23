# AAP.psm1 — module loader
# Convention: Private/*.ps1 are internal helpers, Public/*.ps1 are exported functions.
# Dot-source Private first so Public functions can reference them at parse time.

$ErrorActionPreference = 'Stop'

# Module-scoped state. Connect-AAPController populates this; everything else reads it.
$script:AAPContext = $null

foreach ($folder in @('Private', 'Public')) {
    $path = Join-Path $PSScriptRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' -File | ForEach-Object {
            . $_.FullName
        }
    }
}

# Export only what the manifest declares — defensive against accidentally
# exporting helpers that happen to be named like cmdlets.
Export-ModuleMember -Function @(
    'Connect-AAPController'
    'Invoke-AAPJobTemplate'
    'Get-AAPJob'
    'Get-AAPJobStdout'
    'Stop-AAPJob'
    'Wait-AAPJob'
    'Resolve-AAPJobTemplate'
)
