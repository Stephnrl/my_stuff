# 1. Connect to MS Graph (US Government Environment)
# We need User.Read.All to read all profiles.
Connect-MgGraph -Scopes "User.Read.All" -Environment USGov

# Define your domain and suffix variables to make the script reusable
$Domain = "abcorp.com"
$AdminSuffix = "-az" 

Write-Host "Fetching all '$AdminSuffix' accounts from Entra ID..." -ForegroundColor Cyan

# 2. Get all users that include the -az in their UPN
# Note: We perform a 'EndsWith' filter for efficiency. 
# We explicitly request AccountEnabled and DisplayName properties.
$AzUsers = Get-MgUser -Filter "endsWith(userPrincipalName,'$AdminSuffix@$Domain')" -All -Property Id, DisplayName, UserPrincipalName, AccountEnabled

$Report = @()

foreach ($AzAccount in $AzUsers) {
    
    # 3. Derive the 'Standard' UPN
    # This replaces 'first.last-az@abcorp.com' with 'first.last@abcorp.com'
    $DerivedStandardUPN = $AzAccount.UserPrincipalName.Replace("$AdminSuffix@$Domain", "@$Domain")
    
    Write-Host "Processing $($AzAccount.UserPrincipalName)... Looking for $DerivedStandardUPN" -NoNewline

    # 4. Search for the Standard User
    # We use a try/catch or simple variable check. The -ErrorAction SilentlyContinue prevents red text if not found.
    $StandardAccount = Get-MgUser -Filter "userPrincipalName eq '$DerivedStandardUPN'" -Property Id, AccountEnabled -ErrorAction SilentlyContinue

    $Status = "Healthy"
    $ActionRequired = $false

    # 5. Logic Checks
    if ([string]::IsNullOrWhiteSpace($StandardAccount)) {
        # SCENARIO 1: Standard account is completely gone (Deleted from AD)
        $Status = "ORPHANED - Standard Account Not Found"
        $ActionRequired = $true
        Write-Host " -> ORPHAN DETECTED" -ForegroundColor Red
    }
    elseif ($StandardAccount.AccountEnabled -eq $false) {
        # SCENARIO 2: Standard account exists but is disabled in AD/Entra
        $Status = "RISK - Standard Account Disabled"
        $ActionRequired = $true
        Write-Host " -> DISABLED MATCH DETECTED" -ForegroundColor Yellow
    }
    else {
        # SCENARIO 3: Both active
        Write-Host " -> OK" -ForegroundColor Green
    }

    # 6. Add to Report if actionable (or remove the 'If' to see everyone)
    if ($ActionRequired) {
        $Report += [PSCustomObject]@{
            AdminUPN             = $AzAccount.UserPrincipalName
            AdminID              = $AzAccount.Id
            AdminEnabled         = $AzAccount.AccountEnabled
            StandardUPN_Searched = $DerivedStandardUPN
            StandardStatus       = $Status
        }
    }
}

# 7. Export results
$CsvPath = "C:\Temp\GovCloud_AdminAudit.csv"
$Report | Export-Csv -Path $CsvPath -NoTypeInformation

Write-Host "---"
Write-Host "Audit Complete. Found $( $Report.Count ) issues."
Write-Host "Report saved to: $CsvPath" -ForegroundColor Cyan
