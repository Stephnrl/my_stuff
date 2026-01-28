# 1. The Key Vault Premium (HSM-backed)
resource "azurerm_key_vault" "code_signing" {
  name                        = "kv-codesigning-prod"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium" # Required for HSM keys

  # Security & Access
  enable_rbac_authorization   = true  # Disables Access Policies, uses RBAC only
  public_network_access_enabled = false # Disables the public endpoint

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  soft_delete_retention_days = 90
  purge_protection_enabled   = true
}

# 2. Private Endpoint for the Vault
resource "azurerm_private_endpoint" "kv_pe" {
  name                = "pe-codesigning-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = var.runner_subnet_id # Subnet where your GitHub Runner lives

  private_service_connection {
    name                           = "psc-codesigning-kv"
    private_connection_resource_id = azurerm_key_vault.code_signing.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv_dns.id]
  }
}

# 3. RBAC Role Assignment (The "Key Vault Certificates Officer" role)
resource "azurerm_role_assignment" "runner_kv_access" {
  scope                = azurerm_key_vault.code_signing.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id # The SPN running the Action
}
