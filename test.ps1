function Test-KeyVaultCredentials {
    <#
    .SYNOPSIS
        Tests if credentials can be retrieved from a Key Vault
    
    .DESCRIPTION
        Validates Azure authentication, Key Vault access, and JSON format 
        without returning or exposing credentials
    
    .PARAMETER SecurityId
        The security ID (Key Vault name) to test
    
    .PARAMETER SecretName
        Name of the secret to test (default: "credentials")
    
    .PARAMETER Detailed
        Show detailed test results including auth context
    
    .EXAMPLE
        Test-KeyVaultCredentials -SecurityId "622"
        # Returns $true if successful, $false otherwise
    
    .EXAMPLE
        Test-KeyVaultCredentials -SecurityId "622" -Detailed
        # Shows detailed information about the test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecurityId,
        
        [Parameter(Mandatory = $false)]
        [string]$SecretName = "credentials",
        
        [switch]$Detailed
    )
    
    $testResults = @{
        Success = $false
        AuthenticationValid = $false
        VaultAccessible = $false
        SecretExists = $false
        JsonValid = $false
        RequiredPropertiesExist = $false
        ErrorMessage = ""
    }
    
    try {
        # Test 1: Azure CLI Authentication
        Write-Verbose "Testing Azure CLI authentication..."
        $authContext = Get-AzureCliAuthContext
        
        if ($authContext) {
            $testResults.AuthenticationValid = $true
            if ($Detailed) {
                Write-Host "✓ Authentication: $($authContext.DisplayName) [$($authContext.AuthType)]"
            }
        } else {
            $testResults.ErrorMessage = "Not authenticated to Azure CLI"
            throw $testResults.ErrorMessage
        }
        
        # Test 2: Key Vault Access
        Write-Verbose "Testing Key Vault accessibility..."
        $vaultExists = Test-KeyVaultExists -VaultName $SecurityId
        
        if ($vaultExists) {
            $testResults.VaultAccessible = $true
            if ($Detailed) {
                Write-Host "✓ Key Vault '$SecurityId' is accessible"
            }
        } else {
            $testResults.ErrorMessage = "Key Vault '$SecurityId' not found or not accessible"
            throw $testResults.ErrorMessage
        }
        
        # Test 3: Secret Retrieval
        Write-Verbose "Testing secret retrieval..."
        $secretJson = Get-KeyVaultSecretValue -VaultName $SecurityId -SecretName $SecretName -SuppressError
        
        if ($secretJson) {
            $testResults.SecretExists = $true
            if ($Detailed) {
                Write-Host "✓ Secret '$SecretName' exists in vault"
            }
        } else {
            $testResults.ErrorMessage = "Secret '$SecretName' not found in Key Vault '$SecurityId'"
            throw $testResults.ErrorMessage
        }
        
        # Test 4: JSON Validation
        Write-Verbose "Testing JSON structure..."
        try {
            $parsed = $secretJson | ConvertFrom-Json
            $testResults.JsonValid = $true
            if ($Detailed) {
                Write-Host "✓ Secret contains valid JSON"
            }
        } catch {
            $testResults.ErrorMessage = "Secret does not contain valid JSON"
            throw $testResults.ErrorMessage
        }
        
        # Test 5: Required Properties
        Write-Verbose "Testing required properties..."
        if ($parsed.adminUser -and $parsed.adminPassword) {
            $testResults.RequiredPropertiesExist = $true
            if ($Detailed) {
                Write-Host "✓ Required properties (adminUser, adminPassword) exist"
            }
        } else {
            $testResults.ErrorMessage = "Secret missing required properties (adminUser and/or adminPassword)"
            throw $testResults.ErrorMessage
        }
        
        # All tests passed
        $testResults.Success = $true
        
        if (-not $Detailed) {
            Write-Host "✅ Key Vault '$SecurityId' is properly configured and accessible"
        } else {
            Write-Host "`n✅ All tests passed for Security ID: $SecurityId"
        }
        
        return $true
    }
    catch {
        if ($Detailed) {
            Write-Host "`n❌ Test failed: $($testResults.ErrorMessage)" -ForegroundColor Red
            Write-Host "`nTest Results:" -ForegroundColor Yellow
            Write-Host "  Authentication Valid: $($testResults.AuthenticationValid)"
            Write-Host "  Vault Accessible: $($testResults.VaultAccessible)"
            Write-Host "  Secret Exists: $($testResults.SecretExists)"
            Write-Host "  JSON Valid: $($testResults.JsonValid)"
            Write-Host "  Required Properties: $($testResults.RequiredPropertiesExist)"
        } else {
            Write-Warning "Test failed for Key Vault '$SecurityId': $($testResults.ErrorMessage)"
        }
        
        return $false
    }
}
