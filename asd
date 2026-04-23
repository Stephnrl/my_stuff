<#
.SYNOPSIS
    GitHub Actions entrypoint for the launch-aap-job composite action.
.DESCRIPTION
    Reads INPUT_* environment variables (GitHub Actions convention for composite
    action inputs), imports the AAP module, and orchestrates: connect → launch →
    wait → write outputs. All actual logic lives in the module so it's testable
    independently of the GHA harness.

    Inputs are read from env vars rather than parameters because that's how
    GitHub Actions plumbs `with:` values into composite action steps.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ----------------------------------------------------------------------------
# Helpers for GHA contract
# ----------------------------------------------------------------------------
function Get-RequiredInput {
    param([string]$Name)
    $value = [Environment]::GetEnvironmentVariable("INPUT_$Name")
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required input '$($Name.ToLower())' was not provided."
    }
    $value
}

function Get-OptionalInput {
    param([string]$Name, [string]$Default = '')
    $value = [Environment]::GetEnvironmentVariable("INPUT_$Name")
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    $value
}

function Set-ActionOutput {
    param([string]$Name, [string]$Value)
    if (-not $env:GITHUB_OUTPUT) {
        Write-Verbose "GITHUB_OUTPUT not set — skipping output '$Name'"
        return
    }
    # Multi-line safe via heredoc syntax — even though our values are single-line today,
    # using the delimiter form means we don't break if a value ever contains a newline.
    $delim = "EOF_$([guid]::NewGuid().ToString('N'))"
    @(
        "$Name<<$delim"
        $Value
        $delim
    ) | Add-Content -Path $env:GITHUB_OUTPUT
}

# ----------------------------------------------------------------------------
# Import the module
# ----------------------------------------------------------------------------
$moduleManifest = Join-Path $PSScriptRoot '..' 'AAP' 'AAP.psd1'
Import-Module $moduleManifest -Force

# ----------------------------------------------------------------------------
# Read inputs (GHA composite uses INPUT_<NAME-UPPERCASED-WITH-UNDERSCORES>)
# ----------------------------------------------------------------------------
$aapUrl              = Get-RequiredInput 'AAP_URL'
$aapToken            = Get-RequiredInput 'AAP_TOKEN'
$jobTemplate         = Get-RequiredInput 'JOB_TEMPLATE'
$limit               = Get-OptionalInput 'LIMIT'
$extraVarsJson       = Get-OptionalInput 'EXTRA_VARS' '{}'
$inventory           = Get-OptionalInput 'INVENTORY'
$timeoutSeconds      = [int](Get-OptionalInput 'TIMEOUT_SECONDS' '3600')
$pollIntervalSeconds = [int](Get-OptionalInput 'POLL_INTERVAL_SECONDS' '15')
$failOnFailure       = (Get-OptionalInput 'FAIL_ON_JOB_FAILURE' 'true') -eq 'true'

# Parse and validate extra_vars before doing anything network-y
try {
    $extraVars = $extraVarsJson | ConvertFrom-Json -AsHashtable
}
catch {
    throw "extra-vars input is not valid JSON: $($_.Exception.Message)"
}

# ----------------------------------------------------------------------------
# Orchestrate
# ----------------------------------------------------------------------------
Connect-AAPController -BaseUrl $aapUrl -Token $aapToken

$launchParams = @{
    JobTemplate = $jobTemplate
    ExtraVars   = $extraVars
}
if ($limit)     { $launchParams.Limit     = $limit }
if ($inventory) { $launchParams.Inventory = $inventory }

$launched = Invoke-AAPJobTemplate @launchParams

# Write outputs immediately after launch so they're available even if Wait throws
Set-ActionOutput 'job-id'  "$($launched.id)"
Set-ActionOutput 'job-url' $launched.ui_url

try {
    $finalJob = Wait-AAPJob `
        -Id $launched.id `
        -TimeoutSeconds $timeoutSeconds `
        -PollIntervalSeconds $pollIntervalSeconds `
        -FailOnJobFailure $failOnFailure

    Set-ActionOutput 'status' $finalJob.status
}
catch {
    Set-ActionOutput 'status' 'failed'
    throw
}
