Connect-MgGraph -Environment USGov -Scopes "Application.ReadWrite.All"
# USGovDoD for L5

$sp = Get-MgServicePrincipal -Filter "appId eq '<appId>'"
Update-MgServicePrincipal -ServicePrincipalId $sp.Id -PreferredSingleSignOnMode "saml"


Get-MgServicePrincipal -Filter "appId eq '<appId>'" | Select-Object DisplayName, PreferredSingleSignOnMode



$app = Get-MgApplication -Filter "appId eq '<appId>'"
Update-MgApplication -ApplicationId $app.Id `
  -IdentifierUris @("https://github-nonprod.abc.com") `
  -Web @{ RedirectUris = @("https://github-nonprod.abc.com/saml/consume") }

# generate the SAML signing certificate
$sp = Get-MgServicePrincipal -Filter "appId eq '<appId>'"
$cert = Add-MgServicePrincipalTokenSigningCertificate -ServicePrincipalId $sp.Id `
  -BodyParameter @{ displayName = "CN=github-nonprod-saml" }
Update-MgServicePrincipal -ServicePrincipalId $sp.Id `
  -PreferredTokenSigningKeyThumbprint $cert.Thumbprint
