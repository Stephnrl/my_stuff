function Get-AAPJobStdout {
    <#
    .SYNOPSIS
        Returns the stdout of an AAP job as plain text.
    .PARAMETER Id
        Numeric job ID.
    .PARAMETER Tail
        Return only the last N lines. Useful for failure triage.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('JobId')]
        [int]$Id,

        [int]$Tail
    )
    process {
        $stdout = Invoke-AAPRestMethod -Path "/api/controller/v2/jobs/$Id/stdout/?format=txt&content_encoding=raw"

        if ($PSBoundParameters.ContainsKey('Tail')) {
            return ($stdout -split "`n" | Select-Object -Last $Tail) -join "`n"
        }
        $stdout
    }
}
