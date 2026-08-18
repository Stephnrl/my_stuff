# POA&M state, SBOMs, and raw scan output.
#
# This account holds an enumerated list of exploitable weaknesses in your
# images. Treat it as CUI: no public network access, no shared keys, and a
# retention policy your assessor will accept.

resource "azurerm_storage_account" "gate" {
  name                = replace("st${local.name_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location

  account_tier             = "Standard"
  account_replication_type = var.storage_replication
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  # Force OIDC/Entra auth. Shared keys would let anyone holding the key read
  # every team's vulnerability posture, and they never rotate on their own.
  shared_access_key_enabled = false
  public_network_access_enabled = var.enable_private_endpoint ? false : true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_days
    }

    change_feed_enabled = true
  }

  network_rules {
    # Runner subnets need an explicit allow when the private endpoint is off.
    default_action             = var.enable_private_endpoint ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.runner_subnet_ids
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "poam" {
  name                  = "poam"
  storage_account_id    = azurerm_storage_account.gate.id
  container_access_type = "private"
}

# Immutability is what makes the POA&M tamper-evident. A time-based policy in
# unlocked mode is right for rollout; lock it once retention is agreed, because
# a locked policy CANNOT be shortened or removed afterwards - only extended.
resource "azapi_resource" "poam_immutability" {
  count = var.enable_immutability ? 1 : 0

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies@2023-05-01"
  name      = "default"
  parent_id = azurerm_storage_container.poam.id

  body = {
    properties = {
      immutabilityPeriodSinceCreationInDays = var.immutability_days
      allowProtectedAppendWrites            = true
    }
  }
}

# Age out raw scan JSON aggressively; keep POA&M history for the long haul.
resource "azurerm_storage_management_policy" "gate" {
  storage_account_id = azurerm_storage_account.gate.id

  rule {
    name    = "archive-poam-history"
    enabled = true
    filters {
      prefix_match = ["poam/history"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 90
        tier_to_archive_after_days_since_modification_greater_than = 365
      }
    }
  }

  rule {
    name    = "expire-raw-scans"
    enabled = true
    filters {
      prefix_match = ["poam/raw"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than       = var.raw_scan_retention_days
      }
    }
  }
}

resource "azurerm_private_endpoint" "storage" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "pe-${local.name_prefix}-blob"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.name_prefix}-blob"
    private_connection_resource_id = azurerm_storage_account.gate.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id == "" ? [] : [1]
    content {
      name                 = "default"
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }

  tags = local.tags
}

# The gate's federated identity writes POA&M state. Data Contributor rather
# than Owner: it never needs to change container ACLs or policies.
resource "azurerm_role_assignment" "gate_blob_write" {
  scope                = azurerm_storage_account.gate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.gate_principal_id
}

# Auditors and the security team read but never write.
resource "azurerm_role_assignment" "auditor_blob_read" {
  for_each = toset(var.auditor_principal_ids)

  scope                = azurerm_storage_account.gate.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}
