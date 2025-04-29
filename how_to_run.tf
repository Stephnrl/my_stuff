# Define your providers
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

provider "azurerm" {
  features {}
}

# Reference existing resources
data "azurerm_virtual_network" "existing" {
  name                = "existing-vnet"
  resource_group_name = "existing-rg"
}

data "azurerm_subnet" "existing" {
  name                 = "existing-subnet"
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = data.azurerm_virtual_network.existing.resource_group_name
}

data "azurerm_key_vault" "existing" {
  name                = "existing-keyvault"
  resource_group_name = "existing-rg"
}

data "azurerm_key_vault_key" "encryption" {
  name         = "vm-encryption-key"
  key_vault_id = data.azurerm_key_vault.existing.id
}

data "azurerm_storage_account" "existing" {
  name                = "existingdiagstorageacct"
  resource_group_name = "existing-rg"
}

# Module instantiation
module "fedramp_linux_vm" {
  source = "./modules/azure-fedramp-linux-vm" # Path to your module

  resource_group_name = "vm-resource-group"
  location            = "eastus"
  vm_name             = "fedramp-linux-vm"
  vm_size             = "Standard_D4s_v3"
  admin_username      = "azureadmin"
  ssh_public_key      = file("~/.ssh/id_rsa.pub")
  
  subnet_id           = data.azurerm_subnet.existing.id
  key_vault_id        = data.azurerm_key_vault.existing.id
  key_vault_key_url   = data.azurerm_key_vault_key.encryption.id
  storage_account_uri = data.azurerm_storage_account.existing.primary_blob_endpoint
  
  tags = {
    Environment = "Production"
    Department  = "IT Security"
    Compliance  = "FedRAMP"
  }
  
  # Optional customizations
  os_disk_type     = "Premium_LRS"
  os_disk_size_gb  = 256
  
  # Use a specific image
  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  
  enable_accelerated_networking = true
  enable_automatic_updates      = true
}

# Outputs
output "vm_id" {
  value = module.fedramp_linux_vm.vm_id
}

output "vm_name" {
  value = module.fedramp_linux_vm.vm_name
}

output "vm_identity_principal_id" {
  value = module.fedramp_linux_vm.vm_identity_principal_id
}

output "private_ip_address" {
  value = module.fedramp_linux_vm.private_ip_address
}
