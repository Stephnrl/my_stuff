function Write-AAPLog {
    <#
    .SYNOPSIS
        Writes log output that GitHub Actions renders as annotations when running in CI,
        and as plain colored output when running interactively.
    .DESCRIPTION
        Detects $env:GITHUB_ACTIONS and emits workflow commands (::notice::, ::warning::,
        ::error::) so messages surface in the Actions UI. Falls back to Write-Host with
        colors for local debugging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Notice', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [string]$Title
    )

    $inGHA = $env:GITHUB_ACTIONS -eq 'true'

    if ($inGHA) {
        $titlePart = if ($Title) { " title=$Title" } else { '' }
        switch ($Level) {
            'Notice'  { Write-Host "::notice${titlePart}::$Message" }
            'Warning' { Write-Host "::warning${titlePart}::$Message" }
            'Error'   { Write-Host "::error${titlePart}::$Message" }
            default   { Write-Host $Message }
        }
    }
    else {
        $color = switch ($Level) {
            'Notice'  { 'Cyan' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            default   { 'Gray' }
        }
        Write-Host $Message -ForegroundColor $color
    }
}

function Add-AAPStepSummary {
    <#
    .SYNOPSIS
        Appends markdown to the GitHub Actions step summary. No-op when not in CI.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Markdown
    )
    process {
        if ($env:GITHUB_STEP_SUMMARY) {
            Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Markdown
        }
    }
}
