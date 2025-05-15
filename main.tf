# Get existing virtual network and subnet
data "azurerm_virtual_network" "existing" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name
}

data "azurerm_subnet" "existing" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = var.vnet_resource_group_name
}

# Create resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}-${terraform.workspace}"
  location = var.location
  tags     = merge(var.tags, {
    Environment = terraform.workspace
  })
}

# Random ID for unique resource names
resource "random_id" "unique" {
  byte_length = 4
}

# Storage account for boot diagnostics
resource "azurerm_storage_account" "boot_diagnostics" {
  name                     = "bootdiag${random_id.unique.hex}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  tags                     = var.tags
  min_tls_version          = "TLS1_2"
  
  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [data.azurerm_subnet.existing.id]
    bypass                     = ["AzureServices"]
  }
}

# NSG for the VM
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "${var.vm_name}-nsg-${terraform.workspace}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  # Allow SSH from trusted networks only
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork" # Restrict to virtual network
    destination_address_prefix = "*"
  }
}

# Create network interface for VM
resource "azurerm_network_interface" "vm_nic" {
  name                = "${var.vm_name}-nic-${terraform.workspace}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.existing.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "vm_nsg_association" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Create Ubuntu VM
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${var.vm_name}-${terraform.workspace}"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  tags                  = var.tags

  # IL5 requires FIPS-validated disk encryption
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.boot_diagnostics.primary_blob_endpoint
  }

  # Ensure secure defaults for DoD IL5 compliance
  encryption_at_host_enabled = true
  patch_assessment_mode      = "AutomaticByPlatform"
  patch_mode                 = "AutomaticByPlatform"
  provision_vm_agent         = true
  
  # IL5 extensions
  depends_on = [
    azurerm_key_vault.kv,
    azurerm_key_vault_key.cmk,
  ]
}

# Create Key Vault
resource "azurerm_key_vault" "kv" {
  name                       = "${var.key_vault_name}-${terraform.workspace}-${random_id.unique.hex}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = var.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  tags                       = var.tags
  
  # IL5 requires FIPS-validated cryptography
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [data.azurerm_subnet.existing.id]
  }
}

# Create Customer Managed Key for IL5 compliance
resource "azurerm_key_vault_key" "cmk" {
  count        = var.enable_cmk ? 1 : 0
  name         = "disk-encryption-key"
  key_vault_id = azurerm_key_vault.kv.id
  key_type     = "RSA"
  key_size     = 4096
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
  
  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }
}

# Create Key Vault private endpoint
resource "azurerm_private_endpoint" "kv_pe" {
  name                = "${var.key_vault_name}-pe-${terraform.workspace}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = data.azurerm_subnet.existing.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.key_vault_name}-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}

# Assign permissions to Key Vault for VM identity
resource "azurerm_key_vault_access_policy" "vm_access" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_linux_virtual_machine.vm.identity[0].principal_id

  key_permissions = [
    "Get", "List", "UnwrapKey", "WrapKey"
  ]

  secret_permissions = [
    "Get", "List"
  ]

  certificate_permissions = [
    "Get", "List"
  ]
}

# Assign permissions to Key Vault for admin users
resource "azurerm_key_vault_access_policy" "admin_access" {
  count        = length(var.admin_object_ids)
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = var.tenant_id
  object_id    = var.admin_object_ids[count.index]

  key_permissions = [
    "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List",
    "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update", "Verify", "WrapKey", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy"
  ]

  secret_permissions = [
    "Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"
  ]

  certificate_permissions = [
    "Backup", "Create", "Delete", "DeleteIssuers", "Get", "GetIssuers", "Import",
    "List", "ListIssuers", "ManageContacts", "ManageIssuers", "Purge", "Recover",
    "Restore", "SetIssuers", "Update"
  ]
}

# Create secret for GitHub PAT
resource "azurerm_key_vault_secret" "github_pat" {
  name         = var.github_pat_secret_name
  value        = "REPLACE_WITH_GITHUB_PAT" # This will be updated later via CI/CD
  key_vault_id = azurerm_key_vault.kv.id
  
  depends_on = [
    azurerm_key_vault_access_policy.admin_access
  ]
}

# Set up VM with Ansible using remote-exec
resource "null_resource" "setup_ansible" {
  # Only run this when the VM has been created or changed
  triggers = {
    vm_id = azurerm_linux_virtual_machine.vm.id
  }

  # Copy Ansible directory to the VM
  provisioner "file" {
    source      = var.ansible_path
    destination = "/home/${var.admin_username}/ansible"

    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = file(var.ssh_private_key_path)
      host        = azurerm_network_interface.vm_nic.private_ip_address
      
      # Use bastion host if configured
      bastion_host        = var.use_bastion ? var.bastion_host : null
      bastion_user        = var.use_bastion ? var.bastion_user : null
      bastion_private_key = var.use_bastion ? file(var.bastion_private_key_path) : null
    }
  }

  # Install Ansible and run playbooks
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y python3-pip",
      "sudo pip3 install ansible",
      "cd /home/${var.admin_username}/ansible",
      "ansible-playbook site.yml --connection=local -i 'localhost,'"
    ]

    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = file(var.ssh_private_key_path)
      host        = azurerm_network_interface.vm_nic.private_ip_address
      
      # Use bastion host if configured
      bastion_host        = var.use_bastion ? var.bastion_host : null
      bastion_user        = var.use_bastion ? var.bastion_user : null
      bastion_private_key = var.use_bastion ? file(var.bastion_private_key_path) : null
    }
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm
  ]
}
