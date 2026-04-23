function Wait-AAPJob {
    <#
    .SYNOPSIS
        Polls an AAP job until it reaches a terminal state.
    .DESCRIPTION
        Blocks until the job's status is one of: successful, failed, error, canceled.
        On timeout, attempts to cancel the job and throws. By default throws on
        non-success terminal states; pass -PassThru to return the job object instead.
    .PARAMETER Id
        Numeric job ID. Accepts pipeline input from Invoke-AAPJobTemplate.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait. Default 3600.
    .PARAMETER PollIntervalSeconds
        Seconds between status checks. Default 15.
    .PARAMETER FailOnJobFailure
        When $true (default), throws on failed/error/canceled. When $false, returns
        the job object regardless of status — caller inspects .status.
    .PARAMETER FailureLogTail
        Lines of stdout to dump on failure. Default 200. Set 0 to suppress.
    .EXAMPLE
        Invoke-AAPJobTemplate -JobTemplate 1234 -Limit 'vm-app01' | Wait-AAPJob -TimeoutSeconds 1800
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('JobId')]
        [int]$Id,

        [int]$TimeoutSeconds = 3600,

        [int]$PollIntervalSeconds = 15,

        [bool]$FailOnJobFailure = $true,

        [int]$FailureLogTail = 200
    )
    process {
        $deadline    = (Get-Date).AddSeconds($TimeoutSeconds)
        $lastStatus  = ''
        $terminalOk  = @('successful')
        $terminalBad = @('failed', 'error', 'canceled')
        $inProgress  = @('pending', 'waiting', 'running', 'new')

        while ($true) {
            if ((Get-Date) -ge $deadline) {
                Write-AAPLog "AAP job $Id did not complete within ${TimeoutSeconds}s (last status: $lastStatus)" -Level Error
                Stop-AAPJob -Id $Id -Confirm:$false | Out-Null
                throw "Timeout waiting for AAP job $Id"
            }

            $job = Get-AAPJob -Id $Id
            $status = $job.status

            if ($status -in $terminalOk) {
                Write-AAPLog "AAP job $Id succeeded." -Level Notice
                return $job
            }

            if ($status -in $terminalBad) {
                Write-AAPLog "AAP job $Id ended with status: $status" -Level Error

                if ($FailureLogTail -gt 0) {
                    Write-Host "----- AAP job $Id stdout (last $FailureLogTail lines) -----"
                    try {
                        Get-AAPJobStdout -Id $Id -Tail $FailureLogTail | Write-Host
                    }
                    catch {
                        Write-Host "(failed to fetch stdout: $($_.Exception.Message))"
                    }
                    Write-Host "----------------------------------------------------------"
                }

                if ($FailOnJobFailure) {
                    throw "AAP job $Id finished with status '$status'"
                }
                return $job
            }

            if ($status -in $inProgress) {
                if ($status -ne $lastStatus) {
                    Write-AAPLog "AAP job $Id status: $status"
                    $lastStatus = $status
                }
            }
            else {
                Write-AAPLog "Unrecognized AAP job status '$status' — continuing to poll" -Level Warning
            }

            Start-Sleep -Seconds $PollIntervalSeconds
        }
    }
}
