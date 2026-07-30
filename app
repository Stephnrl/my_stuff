
SP_ID=$(az ad sp show --id <appId> --query id -o tsv)

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_ID" \
  --headers "Content-Type=application/json" \
  --body '{"preferredSingleSignOnMode":"saml"}'
