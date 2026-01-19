# Connect to both services
Connect-MgGraph -Scopes "Application.Read.All"
Connect-AzAccount

# Get App Registrations matching your naming pattern
$appRegistrations = Get-MgApplication -Filter "startswith(displayName, '')" -All | 
    Where-Object { $_.DisplayName -like "*-application-onboarding" }

$results = @()

foreach ($app in $appRegistrations) {
    # Get the Service Principal (Enterprise App) associated with this App Registration
    $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'"
    
    if ($servicePrincipal) {
        # Get Azure RBAC assignments for this Service Principal
        $roleAssignments = Get-AzRoleAssignment -ObjectId $servicePrincipal.Id -ErrorAction SilentlyContinue
        
        foreach ($assignment in $roleAssignments) {
            $results += [PSCustomObject]@{
                AppName           = $app.DisplayName
                AppId             = $app.AppId
                ServicePrincipalId = $servicePrincipal.Id
                RoleDefinitionName = $assignment.RoleDefinitionName
                Scope             = $assignment.Scope
                ScopeType         = switch -Regex ($assignment.Scope) {
                    '^/subscriptions/[^/]+$' { 'Subscription' }
                    '^/subscriptions/.+/resourceGroups/[^/]+$' { 'ResourceGroup' }
                    '^/subscriptions/.+/resourceGroups/.+/providers' { 'Resource' }
                    '^/$' { 'Root' }
                    default { 'ManagementGroup' }
                }
            }
        }
        
        # If no RBAC assignments found, still include the app
        if (-not $roleAssignments) {
            $results += [PSCustomObject]@{
                AppName           = $app.DisplayName
                AppId             = $app.AppId
                ServicePrincipalId = $servicePrincipal.Id
                RoleDefinitionName = "No RBAC Assignments"
                Scope             = "N/A"
                ScopeType         = "N/A"
            }
        }
    }
}

# Output results
$results | Format-Table -AutoSize

# Export to CSV
$results | Export-Csv -Path "AppRegistrations_RBAC_Report.csv" -NoTypeInformation
