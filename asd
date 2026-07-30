Connect-MgGraph -Environment USGov -Scopes "Application.ReadWrite.All"
# USGovDoD for L5

$sp = Get-MgServicePrincipal -Filter "appId eq '<appId>'"
Update-MgServicePrincipal -ServicePrincipalId $sp.Id -PreferredSingleSignOnMode "saml"


Get-MgServicePrincipal -Filter "appId eq '<appId>'" | Select-Object DisplayName, PreferredSingleSignOnMode
