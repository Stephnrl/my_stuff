resource "azurerm_managed_disk" "os_disk" {
  name                = local.os_disk_name
  location            = var.location
  resource_group_name = var.resource_group_name

  storage_account_type   = var.os_disk_storage_account_type
  create_option          = "FromImage"
  disk_size_gb           = var.os_disk_size_gb
  zone                   = var.zone_id
  disk_encryption_set_id = var.disk_encryption_set_id
  
  # Configure private access
  public_network_access_enabled = false
  network_access_policy         = var.enable_disk_private_access ? "AllowPrivate" : "DenyAll"
  disk_access_id                = var.enable_disk_private_access ? azurerm_disk_access.main[0].id : null

  # Source image reference for OS disk
  image_reference_id = var.vm_image_id != null ? var.vm_image_id : null

  dynamic "encryption_settings" {
    for_each = var.enable_disk_encryption ? [1] : []
    content {
      enabled = true
    }
  }

  tags = merge(local.default_tags, var.extra_tags, var.os_disk_extra_tags)
}

# Create Data Disks with private access
resource "azurerm_managed_disk" "data_disks" {
  for_each = var.storage_data_disk_config

  name                = coalesce(each.value.name, data.azurecaf_name.disk[each.key].result)
  location            = var.location
  resource_group_name = var.resource_group_name

  zone = can(regex("_zrs$", lower(each.value.storage_account_type))) ? null : var.zone_id

  storage_account_type   = each.value.storage_account_type
  create_option          = each.value.create_option
  disk_size_gb           = each.value.disk_size_gb
  source_resource_id     = contains(["Copy", "Restore"], each.value.create_option) ? each.value.source_resource_id : null
  disk_encryption_set_id = var.disk_encryption_set_id

  # Configure private access
  public_network_access_enabled = false
  network_access_policy         = var.enable_disk_private_access ? "AllowPrivate" : "DenyAll"
  disk_access_id                = var.enable_disk_private_access ? azurerm_disk_access.main[0].id : null

  disk_iops_read_write = each.value.disk_iops_read_write
  disk_mbps_read_write = each.value.disk_mbps_read_write
  disk_iops_read_only  = each.value.disk_iops_read_only
  disk_mbps_read_only  = each.value.disk_mbps_read_only

  tags = merge(local.default_tags, var.extra_tags, each.value.extra_tags)
}
