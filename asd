function Connect-AAPController {
    <#
    .SYNOPSIS
        Sets the AAP controller URL and bearer token used by all other AAP cmdlets.
    .DESCRIPTION
        Stores connection state in module scope so subsequent calls don't need to
        repeat the URL and token. Validates connectivity by hitting the /api/ ping
        unless -SkipConnectionTest is specified.
    .PARAMETER BaseUrl
        AAP controller base URL. Trailing slash is stripped.
    .PARAMETER Token
        OAuth2 bearer token for an AAP service user.
    .PARAMETER SkipConnectionTest
        Skip the connectivity probe. Useful in retry loops where you've already validated.
    .EXAMPLE
        Connect-AAPController -BaseUrl 'https://aap.example.gov' -Token $env:AAP_TOKEN
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https?://')]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [switch]$SkipConnectionTest
    )

    $script:AAPContext = [pscustomobject]@{
        BaseUrl     = $BaseUrl.TrimEnd('/')
        Token       = $Token
        ConnectedAt = Get-Date
    }

    if (-not $SkipConnectionTest) {
        try {
            $ping = Invoke-AAPRestMethod -Path '/api/controller/v2/ping/' -Method GET
            Write-Verbose "Connected to AAP $($ping.version) (instance: $($ping.active_node))"
        }
        catch {
            $script:AAPContext = $null
            throw "Failed to connect to AAP at $BaseUrl : $($_.Exception.Message)"
        }
    }
}
