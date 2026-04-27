param([Parameter(Mandatory)] [string]$JFrogUrl)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Register-PSResourceRepository -Name JFrogRepo -Uri $JFrogUrl -Trusted

Install-PSResource -Repository JFrogRepo -Scope AllUsers -TrustRepository -Reinstall `
    -Name Az.Accounts, Az.ApiManagement, MSAL.PS, Microsoft.Graph.Authentication
