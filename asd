############################################
# Network interface (private only, no PIP) #
############################################
resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

############################################
# Virtual machine                          #
############################################
resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.name
  computer_name                   = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.this.id]
  disable_password_authentication = true
  source_image_id                 = var.source_image_id
  tags                            = var.tags

  # Trusted Launch — NIST 800-171 3.14.x (boot integrity)
  secure_boot_enabled = var.enable_trusted_launch
  vtpm_enabled        = var.enable_trusted_launch

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching                = "ReadWrite"
    storage_account_type   = "Premium_LRS"
    disk_size_gb           = var.os_disk_size_gb
    disk_encryption_set_id = var.disk_encryption_set_id
  }

  identity {
    type         = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = var.user_assigned_identity_ids
  }

  boot_diagnostics {
    storage_account_uri = var.boot_diagnostics_storage_uri
  }

  lifecycle {
    # Image version drift is managed by the pipeline — a new Packer build bumps source_image_id
    # intentionally. Ignoring here prevents accidental redeploys on plan.
    ignore_changes = [source_image_id]
  }
}

############################################
# Data disks                               #
############################################
resource "azurerm_managed_disk" "data" {
  for_each = { for d in var.data_disks : d.name => d }

  name                   = each.value.name
  location               = var.location
  resource_group_name    = var.resource_group_name
  storage_account_type   = each.value.storage_account_type
  create_option          = "Empty"
  disk_size_gb           = each.value.disk_size_gb
  disk_encryption_set_id = var.disk_encryption_set_id
  tags                   = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = { for d in var.data_disks : d.name => d }

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = each.value.lun
  caching            = each.value.caching
}

############################################
# Entra ID SSH login (human access)        #
############################################
resource "azurerm_virtual_machine_extension" "aad_ssh" {
  count = var.enable_aad_ssh_login ? 1 : 0

  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  # RBAC role assignments ("Virtual Machine User Login" / "Virtual Machine Administrator Login")
  # belong at the RG or VM scope and are assigned in the calling root module, not here —
  # that keeps the module free of specific group object IDs.

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.data,
  ]
}

############################################
# Azure Monitor Agent (logging)            #
############################################
resource "azurerm_virtual_machine_extension" "ama" {
  count = var.enable_azure_monitor_agent ? 1 : 0

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.33"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags

  # AMA itself has no settings worth passing here — the actual log routing is a DCR
  # (azurerm_monitor_data_collection_rule) + DCR association, which belongs in the
  # root module because it's shared across many VMs.

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.data,
  ]
}
