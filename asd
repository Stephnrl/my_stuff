function Stop-AAPJob {
    <#
    .SYNOPSIS
        Cancels a running AAP job.
    .DESCRIPTION
        Best-effort cancellation. Does not throw if the job is already in a terminal
        state — returns $false in that case so callers can branch on the result.
    .PARAMETER Id
        Numeric job ID.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('JobId')]
        [int]$Id
    )
    process {
        if (-not $PSCmdlet.ShouldProcess("AAP job $Id", 'Cancel')) { return $false }

        try {
            $cancelInfo = Invoke-AAPRestMethod -Path "/api/controller/v2/jobs/$Id/cancel/" -Method GET
            if (-not $cancelInfo.can_cancel) {
                Write-AAPLog "AAP job $Id is no longer cancelable (likely already terminal)" -Level Warning
                return $false
            }
            Invoke-AAPRestMethod -Path "/api/controller/v2/jobs/$Id/cancel/" -Method POST | Out-Null
            Write-AAPLog "Cancelled AAP job $Id" -Level Notice
            return $true
        }
        catch {
            Write-AAPLog "Failed to cancel AAP job ${Id}: $($_.Exception.Message)" -Level Warning
            return $false
        }
    }
}
