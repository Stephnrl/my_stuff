function Get-KeyVaultCredentials {
    <#
    .SYNOPSIS
        Retrieves credentials from Azure Gov Key Vault where Security ID is the vault name
    
    .DESCRIPTION
        Uses Azure CLI to retrieve credentials from Key Vault. 
        The Security ID (e.g., 622, 1211) IS the Key Vault name.
        Returns JSON payload with admin user and password.
    
    .PARAMETER SecurityId
        The security ID which is also the Key Vault name (e.g., 622, 1211)
    
    .PARAMETER SecretName
        Name of the secret within the Key Vault (default: "credentials")
    
    .PARAMETER SetEnvironmentVariables
        Set credentials as environment variables for current session
    
    .PARAMETER MaskValues
        Add credentials to GitHub Actions masked values for security
    
    .EXAMPLE
        $creds = Get-KeyVaultCredentials -SecurityId "622"
        Write-Host "Admin User: $($creds.adminUser)"
    
    .EXAMPLE
        Get-KeyVaultCredentials -SecurityId "622" -SetEnvironmentVariables -MaskValues
        # Now available as $env:ADMIN_USER and $env:ADMIN_PASSWORD
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecurityId,
        
        [Parameter(Mandatory = $false)]
        [string]$SecretName = "credentials",
        
        [switch]$SetEnvironmentVariables,
        
        [switch]$MaskValues
    )
    
    begin {
        Write-Verbose "Retrieving credentials from Key Vault: $SecurityId"
        
        # Use private helper to check GitHub Actions environment
        $isGitHubActions = Test-GitHubActionsEnvironment
        
        if ($isGitHubActions) {
            Write-Host "::group::Retrieving Key Vault Credentials (Security ID: $SecurityId)"
        }
    }
    
    process {
        try {
            # Use private helper to verify authentication
            $authContext = Assert-AzureCliAuthentication
            Write-Verbose "Authenticated as: $($authContext.DisplayName) in $($authContext.Environment)"
            
            # Use private helper to retrieve secret
            $secretJson = Get-KeyVaultSecretValue -VaultName $SecurityId -SecretName $SecretName
            
            # Parse and validate the JSON payload
            $credentials = ConvertFrom-KeyVaultJson -JsonString $secretJson
            
            Write-Host "✅ Successfully retrieved credentials from Security ID: $SecurityId"
            
            # Mask values in GitHub Actions logs if requested
            if ($MaskValues -and $isGitHubActions) {
                Add-GitHubSecretMask -Value $credentials.adminUser
                Add-GitHubSecretMask -Value $credentials.adminPassword
                Write-Verbose "Added credentials to masked values"
            }
            
            # Set as environment variables if requested
            if ($SetEnvironmentVariables) {
                Set-CredentialEnvironmentVariables `
                    -AdminUser $credentials.adminUser `
                    -AdminPassword $credentials.adminPassword `
                    -SecurityId $SecurityId
                
                Write-Host "✅ Set environment variables: ADMIN_USER, ADMIN_PASSWORD, SECURITY_ID"
            }
            
            # Return the credentials object
            return $credentials
        }
        catch {
            if ($isGitHubActions) {
                Write-Host "::error::Failed to retrieve credentials from Security ID $SecurityId`: $_"
            }
            Write-Error "Failed to retrieve Key Vault credentials: $_"
            throw
        }
    }
    
    end {
        if ($isGitHubActions) {
            Write-Host "::endgroup::"
        }
    }
}
