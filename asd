RUN pwsh -NoProfile -Command " \
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null; \
        Register-PSRepository -Name JFrogRepo \
            -SourceLocation '${JFROG_PS_URL}' \
            -PublishLocation '${JFROG_PS_URL}' \
            -InstallationPolicy Trusted; \
        Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted; \
        Install-Module -Repository JFrogRepo -Scope AllUsers -Force -AllowClobber \
            -Name Az, Az.Accounts, Az.ApiManagement, MSAL.PS, Microsoft.Graph \
    "
