function Resolve-AAPJobTemplate {
    <#
    .SYNOPSIS
        Resolves a job template identifier (numeric ID or name) to a numeric ID.
    .DESCRIPTION
        If passed a numeric value, returns it unchanged. Otherwise queries the AAP API
        for a JT with the matching name and returns its ID. Errors if zero or more than
        one match is found.
    .PARAMETER Identifier
        Either a numeric job template ID or a JT name string.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Identifier
    )
    process {
        if ($Identifier -match '^\d+$') {
            return [int]$Identifier
        }

        $encoded = [uri]::EscapeDataString($Identifier)
        $resp = Invoke-AAPRestMethod -Path "/api/controller/v2/job_templates/?name=$encoded"

        if ($resp.count -eq 0) {
            throw "No AAP job template found with name '$Identifier'."
        }
        if ($resp.count -gt 1) {
            throw "Expected exactly 1 AAP job template named '$Identifier', got $($resp.count). Use the numeric ID instead."
        }

        return [int]$resp.results[0].id
    }
}
