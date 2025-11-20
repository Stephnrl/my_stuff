# --- CONFIGURATION ---
$StorageAccountName = "mystorageaccount"
$ContainerName      = "script-state"
$StateFileName      = "known_inactive_users.csv"
$SearchServiceName  = "your-search-service"
$IndexName          = "your-index-name"
# API Key (Admin Key recommended)
$SearchApiKey       = "YOUR_ADMIN_KEY_HERE" 

# Connect to GCC High (For Graph API) - Assuming Managed Identity or existing context
# Connect-MgGraph -Environment USGov -Identity

# ==============================================================================
# STEP 1: Load Yesterday's List (The "Known" List)
# ==============================================================================
$knownUsers = @()
try {
    $ctx = Get-AzStorageAccount -ResourceGroupName "MyResourceGroup" -Name $StorageAccountName
    
    # Check if blob exists
    $blob = Get-AzStorageBlob -Container $ContainerName -Blob $StateFileName -Context $ctx.Context -ErrorAction SilentlyContinue
    
    if ($blob) {
        # Download to temp file
        Get-AzStorageBlobContent -Container $ContainerName -Blob $StateFileName -Destination "." -Context $ctx.Context -Force | Out-Null
        $knownUsers = Import-Csv .\$StateFileName | Select-Object -ExpandProperty Email
        Write-Host "Loaded $($knownUsers.Count) previously processed inactive users." -ForegroundColor Cyan
    }
    else {
        Write-Warning "First Run Detected: No state file found. We will check ALL users."
    }
}
catch {
    Write-Warning "Could not access storage. Proceeding as a fresh run."
}

# ==============================================================================
# STEP 2: Get CURRENT Inactive Users from Azure Search (with PAGING)
# ==============================================================================
Write-Host "Querying Azure Search for inactive users..." -ForegroundColor Cyan

$headers = @{ "api-key" = $SearchApiKey }
# Note the GCC High URL (.azure.us)
$baseUrl = "https://$SearchServiceName.search.azure.us/indexes/$IndexName/docs?search=*&`$filter=active eq false&`$select=email&api-version=2021-04-30-Preview"

$allInactiveUsers = @()
$nextLink = $baseUrl

# --- THE PAGING LOOP ---
do {
    try {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get
        $allInactiveUsers += $response.value
        
        # Check if there is a next page
        if ($response.'@odata.nextLink') {
            $nextLink = $response.'@odata.nextLink'
        } else {
            $nextLink = $null
        }
    }
    catch {
        Write-Error "Failed to query Search: $($_.Exception.Message)"
        $nextLink = $null
    }
} while ($nextLink -ne $null)

Write-Host "Total Inactive Users Found in Index: $($allInactiveUsers.Count)" -ForegroundColor Green

# ==============================================================================
# STEP 3: Calculate the Delta (New Candidates Only)
# ==============================================================================
# If this is the first run, $knownUsers is empty, so we check everyone.
# If this is Day 2, we only check emails that are NOT in $knownUsers.

$usersToCheck = $allInactiveUsers | Where-Object { $_.email -notin $knownUsers }
$countToCheck = $usersToCheck.Count

if ($countToCheck -eq 0) {
    Write-Host "No new inactive users found since last run. Exiting." -ForegroundColor Green
}
else {
    Write-Host "Processing $countToCheck NEW inactive users..." -ForegroundColor Yellow
    
    $riskyAccounts = @()

    # ==============================================================================
    # STEP 4: Check Graph for the Delta Group
    # ==============================================================================
    foreach ($user in $usersToCheck) {
        if ([string]::IsNullOrWhiteSpace($user.email)) { continue }

        $baseEmail = $user.email
        $parts = $baseEmail -split "@"
        
        if ($parts.Count -eq 2) {
            $azUserUPN = "$($parts[0])-az@$($parts[1])"

            try {
                # Check Entra ID (US Gov)
                $entraUser = Get-MgUser -UserId $azUserUPN -Property AccountEnabled -ErrorAction Stop
                
                if ($entraUser.AccountEnabled -eq $true) {
                    Write-Host "[RISK] $azUserUPN is ACTIVE." -ForegroundColor Red
                    $riskyAccounts += [PSCustomObject]@{
                        "OriginalEmail" = $baseEmail
                        "AdminAccount"  = $azUserUPN
                        "Status"        = "Active - Needs Termination"
                    }
                }
                else {
                    Write-Host "[OK] $azUserUPN is disabled." -ForegroundColor Gray
                }
            }
            catch {
                # 404 Not Found - This is the ideal state
                Write-Host "[OK] $azUserUPN not found." -ForegroundColor DarkGray
            }
        }
    }

    # Export Results if Risks Found
    if ($riskyAccounts.Count -gt 0) {
        $reportName = "risky_users_$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
        $riskyAccounts | Export-Csv $reportName -NoTypeInformation
        Write-Host "Found $($riskyAccounts.Count) risky accounts. Saved to $reportName" -ForegroundColor Red
        
        # Optional: Upload report to storage so you can download it later
        # Set-AzStorageBlobContent -File $reportName -Container $ContainerName ...
    }
}

# ==============================================================================
# STEP 5: Update State File (Snapshot for tomorrow)
# ==============================================================================
# We save the FULL list of currently inactive users to be the comparison for tomorrow
$allInactiveUsers | Select-Object @{Name="Email";Expression={$_.email}} | Export-Csv .\$StateFileName -NoTypeInformation

# Upload to Blob Storage
Set-AzStorageBlobContent -File .\$StateFileName -Container $ContainerName -Blob $StateFileName -Context $ctx.Context -Force
Write-Host "State file updated." -ForegroundColor Cyan
