/**
 * # Azure Linux VM Terraform Module
 * 
 * This module creates an Azure Linux Virtual Machine with FedRAMP compliance considerations.
 * It assumes that key prerequisites like Key Vault, storage account, and VNet are already created
 * and will be referenced via data sources.
 * 
 * ## FedRAMP Security Features
 * - Trusted launch enabled for enhanced security
 * - Secure boot and vTPM enabled
 * - System-assigned managed identity for Azure services authentication
 * - Disk encryption using Azure Key Vault
 * - Required security extensions
 * - Security-focused network configuration
 */

# Required providers
terraform {
  required_version = ">=1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

# Variables
variable "resource_group_name" {
  description = "Name of the resource group where VM resources will be created"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Admin username for the virtual machine"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the admin user"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the VM will be connected"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the existing Key Vault for disk encryption"
  type        = string
}

variable "key_vault_key_url" {
  description = "URL of the key in Key Vault for disk encryption"
  type        = string
}

variable "storage_account_uri" {
  description = "URI of the storage account for boot diagnostics"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "os_disk_type" {
  description = "Type of OS disk to use"
  type        = string
  default     = "Premium_LRS"
}

variable "os_disk_size_gb" {
  description = "Size of OS disk in GB"
  type        = number
  default     = 128
}

variable "source_image_reference" {
  description = "Source image reference information"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

variable "enable_accelerated_networking" {
  description = "Enable accelerated networking on the network interface"
  type        = bool
  default     = true
}

variable "enable_automatic_updates" {
  description = "Enable automatic updates on the virtual machine"
  type        = bool
  default     = true
}

# Network Interface
resource "azurerm_network_interface" "vm_nic" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  enable_accelerated_networking = var.enable_accelerated_networking
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(var.tags, {
    FedRAMP = "High"
  })
}

# Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = var.vm_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm_nic.id]

  # FedRAMP-required: Use managed identity for improved security
  identity {
    type = "SystemAssigned"
  }

  # FedRAMP-required: Enable security features with trusted launch
  secure_boot_enabled = true
  vtpm_enabled        = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }

  boot_diagnostics {
    storage_account_uri = var.storage_account_uri
  }

  # FedRAMP-required: Ensure patches are applied
  patch_mode = "AutomaticByPlatform"
  
  # Additional security features
  encryption_at_host_enabled = true

  tags = merge(var.tags, {
    FedRAMP = "High"
  })
}

# Disk encryption set for OS and data disks
resource "azurerm_disk_encryption_set" "vm_encryption" {
  name                = "${var.vm_name}-disk-encryption-set"
  resource_group_name = var.resource_group_name
  location            = var.location
  key_vault_key_id    = var.key_vault_key_url
  
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    FedRAMP = "High"
  })
}

# Key Vault access policy for disk encryption
resource "azurerm_key_vault_access_policy" "disk_encryption" {
  key_vault_id = var.key_vault_id
  
  tenant_id = azurerm_disk_encryption_set.vm_encryption.identity[0].tenant_id
  object_id = azurerm_disk_encryption_set.vm_encryption.identity[0].principal_id
  
  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey"
  ]
}

# VM Extension for Azure Monitor
resource "azurerm_virtual_machine_extension" "azure_monitor" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  tags = merge(var.tags, {
    FedRAMP = "High"
  })
}

# VM Extension for Azure Security
resource "azurerm_virtual_machine_extension" "security_extension" {
  name                       = "AzureSecurityLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm.id
  publisher                  = "Microsoft.Azure.Security"
  type                       = "AzureSecurityLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  tags = merge(var.tags, {
    FedRAMP = "High"
  })
}

# VM Extension for Log Analytics
resource "azurerm_virtual_machine_extension" "oms_agent" {
  name                       = "OmsAgentForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm.id
  publisher                  = "Microsoft.EnterpriseCloud.Monitoring"
  type                       = "OmsAgentForLinux"
  type_handler_version       = "1.13"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "workspaceId": "${data.azurerm_log_analytics_workspace.law.workspace_id}"
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "workspaceKey": "${data.azurerm_log_analytics_workspace.law.primary_shared_key}"
    }
  PROTECTED_SETTINGS

  tags = merge(var.tags, {
    FedRAMP = "High"
  })
}

# Data sources
data "azurerm_log_analytics_workspace" "law" {
  name                = "fedramp-log-analytics-workspace"
  resource_group_name = var.resource_group_name
}

# Outputs
output "vm_id" {
  description = "The ID of the virtual machine"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "vm_name" {
  description = "The name of the virtual machine"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "vm_identity_principal_id" {
  description = "The principal ID of the system-assigned identity"
  value       = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}

output "private_ip_address" {
  description = "The private IP address of the virtual machine"
  value       = azurerm_network_interface.vm_nic.private_ip_address
}
