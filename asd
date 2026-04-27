RUN pwsh -NoProfile -Command " \
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
    Register-PSResourceRepository -Name JFrogRepo \
        -Uri '${JFROG_PS_URL}' \
        -Trusted; \
    Install-PSResource -Repository JFrogRepo -Scope AllUsers -TrustRepository \
        -Name Az.Accounts, Az.ApiManagement, MSAL.PS, Microsoft.Graph.Authentication \
"
