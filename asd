function Invoke-AAPRestMethod {
    <#
    .SYNOPSIS
        Internal wrapper around Invoke-RestMethod for AAP controller API calls.
    .DESCRIPTION
        Centralizes auth header injection, base URL composition, retry on transient
        failures (5xx, 429), and consistent error surfacing. Public functions should
        always go through this rather than calling Invoke-RestMethod directly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body,

        [int]$MaxRetries = 3,

        [int]$RetryDelaySeconds = 5
    )

    if (-not $script:AAPContext) {
        throw "Not connected to an AAP controller. Run Connect-AAPController first."
    }

    $uri = "$($script:AAPContext.BaseUrl)$Path"
    $headers = @{
        'Authorization' = "Bearer $($script:AAPContext.Token)"
        'Accept'        = 'application/json'
    }

    $params = @{
        Uri             = $uri
        Method          = $Method
        Headers         = $headers
        ErrorAction     = 'Stop'
        # AAP can return non-2xx with JSON error bodies — capture them
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
    }

    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $params.Body        = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        $params.ContentType = 'application/json'
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $response = Invoke-RestMethod @params

            # Success
            if ($statusCode -ge 200 -and $statusCode -lt 300) {
                return $response
            }

            # Retryable
            if (($statusCode -eq 429 -or $statusCode -ge 500) -and $attempt -le $MaxRetries) {
                $delay = $RetryDelaySeconds * [math]::Pow(2, $attempt - 1)
                Write-Verbose "AAP returned $statusCode on attempt $attempt — retrying in ${delay}s"
                Start-Sleep -Seconds $delay
                continue
            }

            # Non-retryable error — surface AAP's error body when present
            $errorDetail = if ($response) { ($response | ConvertTo-Json -Depth 5 -Compress) } else { '<no body>' }
            throw "AAP API call failed: $Method $Path returned HTTP $statusCode. Body: $errorDetail"
        }
        catch [System.Net.Http.HttpRequestException] {
            # Network-layer failure (DNS, TLS, connection reset)
            if ($attempt -le $MaxRetries) {
                $delay = $RetryDelaySeconds * [math]::Pow(2, $attempt - 1)
                Write-Verbose "Network error on attempt ${attempt}: $($_.Exception.Message). Retrying in ${delay}s"
                Start-Sleep -Seconds $delay
                continue
            }
            throw
        }
    }
}
