locals {
  # Required for Entra token auth and for private endpoints. Without a custom
  # subdomain the resource only answers on the regional shared hostname, which
  # supports neither.
  subdomain = var.name

  store_key = var.key_vault_id != null && !var.disable_local_auth
  use_pe    = var.private_endpoint_subnet_id != null
}

resource "azurerm_cognitive_account" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "OpenAI"
  sku_name            = "S0"

  custom_subdomain_name = local.subdomain

  # When true, both API keys and Entra work. When false, keys are refused and
  # every caller must present an Entra token -- which removes an entire class
  # of secret-handling problem from your CI.
  local_auth_enabled            = !var.disable_local_auth
  public_network_access_enabled = var.public_network_access_enabled

  identity {
    type = "SystemAssigned"
  }

  # network_acls is only meaningful while public access is on. Applying it with
  # public access disabled is accepted but does nothing.
  dynamic "network_acls" {
    for_each = var.public_network_access_enabled ? [1] : []
    content {
      default_action = length(var.allowed_ip_rules) > 0 ? "Deny" : "Allow"
      ip_rules       = var.allowed_ip_rules
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.public_network_access_enabled || local.use_pe
      error_message = "Public access is disabled and no private endpoint subnet was given. Nothing would be able to reach this resource."
    }
  }
}

resource "azurerm_cognitive_deployment" "this" {
  name                 = var.deployment_name
  cognitive_account_id = azurerm_cognitive_account.this.id

  model {
    format  = "OpenAI"
    name    = var.model_name
    version = var.model_version
  }

  sku {
    name     = var.sku_name
    capacity = var.capacity
  }
}

# Inference-plane access only. Deliberately not "Cognitive Services
# Contributor", which would also grant key retrieval and management rights.
resource "azurerm_role_assignment" "runner_inference" {
  for_each = toset(var.runner_principal_ids)

  scope                = azurerm_cognitive_account.this.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = each.value
}

resource "azurerm_private_endpoint" "this" {
  count = local.use_pe ? 1 : 0

  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azurerm_cognitive_account.this.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }
}

# Only created when key auth is left enabled. Prefer Entra and skip this.
resource "azurerm_key_vault_secret" "api_key" {
  count = local.store_key ? 1 : 0

  name         = "${var.name}-openai-key"
  value        = azurerm_cognitive_account.this.primary_access_key
  key_vault_id = var.key_vault_id
}
