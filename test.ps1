# Private/KeyVaultHelpers.ps1
# Internal helper functions - not exported

function Assert-AzureCliAuthentication {
    <#
    .SYNOPSIS
        Verifies Azure CLI authentication and returns context
    .DESCRIPTION
        Internal helper that checks Azure CLI auth and throws if not authenticated
    #>
    [CmdletBinding()]
    param()
    
    $context = Get-AzureCliAuthContext
    
    if (-not $context) {
        throw "Not logged in to Azure. Please run 'az login' or use azure/login action"
    }
    
    return $context
}

function Get-AzureCliAuthContext {
    <#
    .SYNOPSIS
        Gets current Azure CLI authentication context
    .DESCRIPTION
        Returns auth details handling both SPN and User authentication
    #>
    [CmdletBinding()]
    param()
    
    try {
        # Check if Azure CLI is available
        $azCmd = Get-Command az -ErrorAction SilentlyContinue
        if (-not $azCmd) {
            Write-Warning "Azure CLI is not installed or not in PATH"
            return $null
        }
        
        # Get account info
        $accountInfo = az account show 2>$null | ConvertFrom-Json
        
        if (-not $accountInfo) {
            return $null
        }
        
        # Build context object
        $context = [PSCustomObject]@{
            SubscriptionId = $accountInfo.id
            SubscriptionName = $accountInfo.name
            TenantId = $accountInfo.tenantId
            Environment = $accountInfo.environmentName
            IsDefault = $accountInfo.isDefault
            State = $accountInfo.state
        }
        
        # Add authentication-specific properties
        if ($accountInfo.user.type -eq "servicePrincipal") {
            $context | Add-Member -NotePropertyName AuthType -NotePropertyValue "ServicePrincipal"
            $context | Add-Member -NotePropertyName ClientId -NotePropertyValue $accountInfo.user.name
            $context | Add-Member -NotePropertyName DisplayName -NotePropertyValue "SPN: $($accountInfo.user.name)"
        } else {
            $context | Add-Member -NotePropertyName AuthType -NotePropertyValue "User"
            $context | Add-Member -NotePropertyName UserName -NotePropertyValue $accountInfo.user.name
            $context | Add-Member -NotePropertyName DisplayName -NotePropertyValue $accountInfo.user.name
        }
        
        return $context
    }
    catch {
        Write-Verbose "Failed to get Azure CLI context: $_"
        return $null
    }
}

function Get-KeyVaultSecretValue {
    <#
    .SYNOPSIS
        Retrieves a secret value from Key Vault using Azure CLI
    .DESCRIPTION
        Internal helper that handles the actual Azure CLI call to get secret
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName,
        
        [Parameter(Mandatory = $true)]
        [string]$SecretName,
        
        [switch]$SuppressError
    )
    
    try {
        # Build and execute the Azure CLI command
        $secretValue = az keyvault secret show `
            --vault-name $VaultName `
            --name $SecretName `
            --query value `
            --output tsv `
            2>$null
        
        if (-not $secretValue -and -not $SuppressError) {
            # Get detailed error for better diagnostics
            $errorOutput = az keyvault secret show `
                --vault-name $VaultName `
                --name $SecretName `
                2>&1
            
            $errorMessage = Parse-AzureCliError -ErrorOutput $errorOutput -VaultName $VaultName -SecretName $SecretName
            throw $errorMessage
        }
        
        return $secretValue
    }
    catch {
        if ($SuppressError) {
            return $null
        }
        throw
    }
}

function Test-KeyVaultExists {
    <#
    .SYNOPSIS
        Tests if a Key Vault exists and is accessible
    .DESCRIPTION
        Internal helper to check vault accessibility
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName
    )
    
    try {
        $result = az keyvault show --name $VaultName --query name --output tsv 2>$null
        return ($null -ne $result -and $result -eq $VaultName)
    }
    catch {
        return $false
    }
}

function Parse-AzureCliError {
    <#
    .SYNOPSIS
        Parses Azure CLI error output to provide meaningful error messages
    .DESCRIPTION
        Internal helper to convert Azure CLI errors to user-friendly messages
    #>
    [CmdletBinding()]
    param(
        [string]$ErrorOutput,
        [string]$VaultName,
        [string]$SecretName
    )
    
    if ($ErrorOutput -match "ResourceNotFound") {
        return "Secret '$SecretName' not found in Key Vault '$VaultName'"
    }
    elseif ($ErrorOutput -match "VaultNotFound") {
        return "Key Vault '$VaultName' not found"
    }
    elseif ($ErrorOutput -match "Forbidden") {
        return "Access denied to Key Vault '$VaultName'. Check service principal permissions"
    }
    elseif ($ErrorOutput -match "AuthorizationFailed") {
        return "Authorization failed. The service principal lacks necessary permissions"
    }
    elseif ($ErrorOutput -match "InvalidAuthenticationToken") {
        return "Invalid authentication token. Please re-authenticate"
    }
    else {
        return "Failed to retrieve secret: $ErrorOutput"
    }
}

function ConvertFrom-KeyVaultJson {
    <#
    .SYNOPSIS
        Parses and validates Key Vault JSON secret
    .DESCRIPTION
        Internal helper to parse JSON and validate required properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonString
    )
    
    try {
        $credentials = $JsonString | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse secret as JSON. Ensure the secret contains valid JSON"
    }
    
    # Validate required properties
    if (-not $credentials.adminUser -or -not $credentials.adminPassword) {
        throw "Secret JSON must contain 'adminUser' and 'adminPassword' properties"
    }
    
    return $credentials
}

function Test-GitHubActionsEnvironment {
    <#
    .SYNOPSIS
        Checks if running in GitHub Actions
    .DESCRIPTION
        Internal helper to detect GitHub Actions environment
    #>
    [CmdletBinding()]
    param()
    
    return ($env:GITHUB_ACTIONS -eq 'true')
}

function Add-GitHubSecretMask {
    <#
    .SYNOPSIS
        Adds a value to GitHub Actions secret masking
    .DESCRIPTION
        Internal helper to mask sensitive values in logs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )
    
    if (Test-GitHubActionsEnvironment) {
        Write-Host "::add-mask::$Value"
    }
}

function Set-CredentialEnvironmentVariables {
    <#
    .SYNOPSIS
        Sets credentials as environment variables
    .DESCRIPTION
        Internal helper to set environment variables for current and future steps
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdminUser,
        
        [Parameter(Mandatory = $true)]
        [string]$AdminPassword,
        
        [Parameter(Mandatory = $true)]
        [string]$SecurityId
    )
    
    # Set for current session
    $env:ADMIN_USER = $AdminUser
    $env:ADMIN_PASSWORD = $AdminPassword
    $env:SECURITY_ID = $SecurityId
    
    # Persist for GitHub Actions (future steps in same job)
    if (Test-GitHubActionsEnvironment -and (Test-Path $env:GITHUB_ENV -ErrorAction SilentlyContinue)) {
        Add-Content -Path $env:GITHUB_ENV -Value "ADMIN_USER=$AdminUser"
        Add-Content -Path $env:GITHUB_ENV -Value "ADMIN_PASSWORD=$AdminPassword"
        Add-Content -Path $env:GITHUB_ENV -Value "SECURITY_ID=$SecurityId"
    }
}
