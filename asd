az account show --query "{tenant:tenantId, user:user.name}"
az account get-access-token --resource-type ms-graph --query expiresOn
