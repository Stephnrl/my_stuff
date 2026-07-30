az ad app list --display-name "github" \
  --query "[].{name:displayName, appId:appId, uris:identifierUris, redirect:web.redirectUris}" -o table

# then, for the one you found:
az ad app show --id <appId> --query "{creds:passwordCredentials, certs:keyCredentials, perms:requiredResourceAccess}"
az ad sp show --id <appId> --query "{ssoMode:preferredSingleSignOnMode, tags:tags}"
