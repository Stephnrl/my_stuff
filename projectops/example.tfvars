name                = "projectops-openai"
resource_group_name = "rg-devops-shared"
location            = "eastus2"

model_name      = "gpt-4o"
model_version   = "2024-08-06"
deployment_name = "projectops"
sku_name        = "DataZoneStandard"
capacity        = 10

# Entra only -- no key exists, so none can leak.
disable_local_auth            = true
public_network_access_enabled = false

private_endpoint_subnet_id = "/subscriptions/.../subnets/snet-private-endpoints"
private_dns_zone_ids       = ["/subscriptions/.../privateDnsZones/privatelink.openai.azure.com"]

# Managed identities your self-hosted runners run as.
runner_principal_ids = ["00000000-0000-0000-0000-000000000000"]

tags = {
  owner   = "platform-engineering"
  purpose = "projectops-issue-triage"
}
