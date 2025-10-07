[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AdminSecurityId,
    
    [Parameter(Mandatory = $false)]
    [string]$AdminSecurityDomain = 'snc'
)

# Load utility scripts
function Initialize-Scripts {
    $scriptPath = $PSScriptRoot
    
    Write-Host "Loading utility scripts from: $scriptPath"
    
    # Dot source the Utility.ps1 file
    . "$scriptPath/Utility.ps1"
    
    Write-Host "Utility scripts loaded successfully"
}

# Main execution function
function Invoke-Main {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$AdminSecurityId,
        
        [Parameter(Mandatory = $false)]
        [string]$AdminSecurityDomain = 'snc'
    )
    
    try {
        Write-Host "=========================================="
        Write-Host "Starting deployment script"
        Write-Host "Environment: $Environment"
        Write-Host "=========================================="
        
        # Get admin credentials
        Write-Host "`nRetrieving admin credentials..."
        $adminCreds = Get-KeyVaultSecurityCredentials `
            -Environment $Environment `
            -SecurityId $AdminSecurityId `
            -Domain $AdminSecurityDomain
        
        # Use the credentials
        $adminUserName = $adminCreds.FullUserName
        $adminPassword = $adminCreds.Password
        
        Write-Host "Admin Username: $adminUserName"
        
        # Create PSCredential object
        $securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($adminUserName, $securePassword)
        
        Write-Host "`nCredentials prepared successfully"
        
        Write-Host "`n=========================================="
        Write-Host "Deployment completed successfully"
        Write-Host "=========================================="
        
        return $true
    }
    catch {
        Write-Error "Deployment failed: $_"
        Write-Host "Stack Trace: $($_.ScriptStackTrace)"
        throw
    }
}

# Script entry point
try {
    # Load all utility scripts
    Initialize-Scripts
    
    # Execute main function
    Invoke-Main `
        -Environment $Environment `
        -AdminSecurityId $AdminSecurityId `
        -AdminSecurityDomain $AdminSecurityDomain
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}
