function Get-AAPJob {
    <#
    .SYNOPSIS
        Retrieves an AAP job by ID.
    .PARAMETER Id
        Numeric job ID. Accepts pipeline input from Invoke-AAPJobTemplate.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('JobId')]
        [int]$Id
    )
    process {
        Invoke-AAPRestMethod -Path "/api/controller/v2/jobs/$Id/"
    }
}
