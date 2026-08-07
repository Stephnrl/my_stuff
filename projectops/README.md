# Azure OpenAI module for ProjectOps

Provisions the inference resource `projectops plan` calls. Entra-only and
private-endpoint-only by default — there is no API key to store or rotate.

```hcl
module "projectops_openai" {
  source = "./terraform"

  name                = "projectops-openai"
  resource_group_name = "rg-devops-shared"
  location            = "eastus2"

  disable_local_auth            = true
  public_network_access_enabled = false
  private_endpoint_subnet_id    = data.azurerm_subnet.pe.id
  private_dns_zone_ids          = [azurerm_private_dns_zone.openai.id]
  runner_principal_ids          = [azurerm_user_assigned_identity.runner.principal_id]
}
```

Then wire the outputs into repo **variables** (not secrets — neither value is
sensitive):

```
AZURE_OPENAI_ENDPOINT   = module.projectops_openai.endpoint
AZURE_OPENAI_DEPLOYMENT = module.projectops_openai.deployment_name
```

## Things that will bite you

- **`custom_subdomain_name` is mandatory** for both Entra auth and private
  endpoints. The module sets it from `name`; changing `name` later forces
  replacement of the account.
- **Model availability is per-region.** `terraform apply` fails at deployment
  creation, not at plan time, if the model isn't offered where you put it.
- **`private_dns_zone_ids` is not optional in practice.** Without it the
  private endpoint exists but `*.openai.azure.com` still resolves publicly, so
  traffic leaves your network and you won't notice.
- **`disable_local_auth = true` breaks anything using a key**, including
  Copilot CLI BYOK, which only accepts a static key via env var. Leave keys on
  if you want that path open.
- **Deployment name ≠ model name.** `AZURE_OPENAI_DEPLOYMENT` takes the
  deployment name. A 404 from the API almost always means these were confused.
- **Structured outputs need `gpt-4o` at `2024-08-06` or later** and api-version
  `2024-10-21`+. Older model versions return 400 on `response_format`.

## Runner identity

The plan job authenticates with `azure/login@v2` using a federated credential,
so `id-token: write` is required on the job. Register the federated identity
against `repo:ORG/REPO:ref:refs/heads/main` (or an environment) and grant it
nothing beyond `Cognitive Services OpenAI User` on this resource — inference
only, no key retrieval, no management plane.
