# main.tf

resource "azurerm_shared_image_gallery" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  description         = var.description
  tags                = merge(local.default_tags, var.tags)

  dynamic "sharing" {
    for_each = var.sharing != null ? [var.sharing] : []

    content {
      permission = sharing.value.permission

      dynamic "community_gallery" {
        for_each = sharing.value.community_gallery != null ? [sharing.value.community_gallery] : []

        content {
          eula            = community_gallery.value.eula
          prefix          = community_gallery.value.prefix
          publisher_email = community_gallery.value.publisher_email
          publisher_uri   = community_gallery.value.publisher_uri
        }
      }
    }
  }

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }
}

resource "azurerm_shared_image" "this" {
  for_each = var.shared_image_definitions

  name                = each.value.name
  gallery_name        = azurerm_shared_image_gallery.this.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = each.value.os_type
  
  # Optional attributes with defaults
  accelerated_network_support_enabled = lookup(each.value, "accelerated_network_support_enabled", null)
  architecture                        = lookup(each.value, "architecture", null)
  confidential_vm_enabled             = lookup(each.value, "confidential_vm_enabled", null)
  confidential_vm_supported           = lookup(each.value, "confidential_vm_supported", null)
  description                         = lookup(each.value, "description", null)
  disk_types_not_allowed              = lookup(each.value, "disk_types_not_allowed", null)
  end_of_life_date                    = lookup(each.value, "end_of_life_date", null)
  eula                                = lookup(each.value, "eula", null)
  hyper_v_generation                  = lookup(each.value, "hyper_v_generation", null)
  max_recommended_memory_in_gb        = lookup(each.value, "max_recommended_memory_in_gb", null)
  max_recommended_vcpu_count          = lookup(each.value, "max_recommended_vcpu_count", null)
  min_recommended_memory_in_gb        = lookup(each.value, "min_recommended_memory_in_gb", null)
  min_recommended_vcpu_count          = lookup(each.value, "min_recommended_vcpu_count", null)
  privacy_statement_uri               = lookup(each.value, "privacy_statement_uri", null)
  release_note_uri                    = lookup(each.value, "release_note_uri", null)
  specialized                         = lookup(each.value, "specialized", false)
  trusted_launch_enabled              = lookup(each.value, "trusted_launch_enabled", null)
  trusted_launch_supported            = lookup(each.value, "trusted_launch_supported", null)
  tags                                = lookup(each.value, "tags", {})

  identifier {
    offer     = each.value.identifier.offer
    publisher = each.value.identifier.publisher
    sku       = each.value.identifier.sku
  }

  dynamic "purchase_plan" {
    for_each = lookup(each.value, "purchase_plan", null) != null ? [each.value.purchase_plan] : []

    content {
      name      = purchase_plan.value.name
      product   = purchase_plan.value.product
      publisher = purchase_plan.value.publisher
    }
  }
}

# Management Lock
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-${var.lock.kind}")
  scope      = azurerm_shared_image_gallery.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

# Role Assignments
resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = azurerm_shared_image_gallery.this.id
  condition                              = lookup(each.value, "condition", null)
  condition_version                      = lookup(each.value, "condition_version", null)
  delegated_managed_identity_resource_id = lookup(each.value, "delegated_managed_identity_resource_id", null)
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = lookup(each.value, "skip_service_principal_aad_check", null)
}

# Added move blocks for migration from existing resources
moved {
  from = azurerm_shared_image_gallery.shared_image_gallery
  to   = azurerm_shared_image_gallery.this
}

moved {
  from = azurerm_shared_image.shared_image
  to   = azurerm_shared_image.this
}
