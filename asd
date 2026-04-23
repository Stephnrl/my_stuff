function Invoke-AAPJobTemplate {
    <#
    .SYNOPSIS
        Launches an AAP job template.
    .DESCRIPTION
        POSTs to the JT launch endpoint with optional limit, extra_vars, and inventory
        overrides. Returns the launched job object (containing .id, .url, .status, etc.).
        Does NOT wait for completion — pipe the result to Wait-AAPJob for that.
    .PARAMETER JobTemplate
        Numeric ID or name of the JT to launch.
    .PARAMETER Limit
        Inventory limit pattern. Optional but recommended for "configure one host" workflows.
    .PARAMETER ExtraVars
        Hashtable of extra_vars. Will be JSON-serialized.
    .PARAMETER Inventory
        Override inventory (ID or name). Optional.
    .EXAMPLE
        Invoke-AAPJobTemplate -JobTemplate 'rhel9-configure' -Limit 'vm-app01' -ExtraVars @{
            target_host = 'vm-app01'
            cmmc_level  = '2'
        } | Wait-AAPJob
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$JobTemplate,

        [string]$Limit,

        [hashtable]$ExtraVars = @{},

        [string]$Inventory
    )

    $jtId = Resolve-AAPJobTemplate -Identifier $JobTemplate

    $payload = @{
        extra_vars = $ExtraVars
    }
    if ($Limit)     { $payload.limit = $Limit }
    if ($Inventory) {
        # Accept either numeric ID or name; AAP will reject bad values
        $payload.inventory = if ($Inventory -match '^\d+$') { [int]$Inventory } else { $Inventory }
    }

    Write-AAPLog "Launching AAP job template $jtId" -Level Info

    $job = Invoke-AAPRestMethod `
        -Path "/api/controller/v2/job_templates/$jtId/launch/" `
        -Method POST `
        -Body $payload

    $jobUrl = "$($script:AAPContext.BaseUrl)/#/jobs/playbook/$($job.id)/output"

    Write-AAPLog "Launched AAP job $($job.id) — $jobUrl" -Level Notice -Title 'AAP Job'

    @"
### AAP Job Launched

- **Job ID:** $($job.id)
- **Template:** $jtId
- **Link:** [$jobUrl]($jobUrl)
"@ | Add-AAPStepSummary

    # Augment the response with the UI URL — saves callers from rebuilding it
    $job | Add-Member -NotePropertyName 'ui_url' -NotePropertyValue $jobUrl -PassThru
}
