BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "../modules/KeyVaultUtils/KeyVaultUtils.psd1"
    Import-Module $modulePath -Force
}

Describe "KeyVaultUtils Module" {
    Context "Module Structure" {
        It "Should have a valid manifest" {
            $modulePath = Join-Path $PSScriptRoot "../modules/KeyVaultUtils/KeyVaultUtils.psd1"
            { Test-ModuleManifest -Path $modulePath -ErrorAction Stop } | Should -Not -Throw
        }
        
        It "Should export Get-KeyVaultCredentials function" {
            Get-Command -Module KeyVaultUtils -Name Get-KeyVaultCredentials | Should -Not -BeNullOrEmpty
        }
        
        It "Should export Test-KeyVaultCredentials function" {
            Get-Command -Module KeyVaultUtils -Name Test-KeyVaultCredentials | Should -Not -BeNullOrEmpty
        }
        
        It "Should NOT export private helper functions" {
            # These should not be accessible
            { Get-Command -Module KeyVaultUtils -Name Get-AzureCliAuthContext } | Should -Throw
            { Get-Command -Module KeyVaultUtils -Name Get-KeyVaultSecretValue } | Should -Throw
        }
    }
    
    Context "Function Parameters" {
        It "Get-KeyVaultCredentials should have mandatory SecurityId parameter" {
            $cmd = Get-Command Get-KeyVaultCredentials
            $param = $cmd.Parameters["SecurityId"]
            $param.Attributes.Mandatory | Should -Contain $true
        }
        
        It "Test-KeyVaultCredentials should have mandatory SecurityId parameter" {
            $cmd = Get-Command Test-KeyVaultCredentials
            $param = $cmd.Parameters["SecurityId"]
            $param.Attributes.Mandatory | Should -Contain $true
        }
    }
}

# Integration tests (only run if authenticated to Azure)
Describe "KeyVaultUtils Integration" -Tag "Integration" {
    BeforeAll {
        # Check if we're authenticated
        $authenticated = $null -ne (az account show 2>$null | ConvertFrom-Json)
        
        if (-not $authenticated) {
            Set-ItResult -Skipped -Because "Not authenticated to Azure"
        }
    }
    
    Context "Azure Authentication" {
        It "Should detect Azure CLI authentication" {
            # This test uses private function indirectly through Test-KeyVaultCredentials
            # We're testing that it properly detects lack of valid vault without throwing auth errors
            Test-KeyVaultCredentials -SecurityId "nonexistent-vault-99999" -ErrorAction SilentlyContinue | Should -Be $false
        }
    }
}
