terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  environment = "usgovernment"
}

# --- Data lookups (replace with your actual IDs/names) -----------------------

data "azurerm_shared_image_version" "rhel9" {
  name                = "latest" # or pin to a specific semver
  image_name          = "rhel9-hardened"
  gallery_name        = "gal_platform_prod"
  resource_group_name = "rg-gallery-prod"
}

data "azurerm_subnet" "app" {
  name                 = "snet-app"
  virtual_network_name = "vnet-app-prod"
  resource_group_name  = "rg-network-prod"
}

data "azurerm_disk_encryption_set" "cmk" {
  name                = "des-cmk-prod"
  resource_group_name = "rg-kv-prod"
}

# --- VM ----------------------------------------------------------------------

module "rhel9_app01" {
  source = "../../modules/linux-vm"

  name                = "vm-app01"
  resource_group_name = "rg-app-prod"
  location            = "usgovvirginia"

  vm_size              = "Standard_D4s_v5"
  admin_ssh_public_key = var.aap_admin_public_key # sourced from Key Vault / GH secret
  subnet_id            = data.azurerm_subnet.app.id
  source_image_id      = data.azurerm_shared_image_version.rhel9.id

  disk_encryption_set_id = data.azurerm_disk_encryption_set.cmk.id

  data_disks = [
    {
      name         = "vm-app01-data01"
      lun          = 0
      disk_size_gb = 256
    }
  ]

  tags = {
    environment         = "prod"
    owner               = "platform-eng"
    cost_center         = "12345"
    data_classification = "cui"
    cmmc_level          = "2"
  }
}

# --- Post-create: RBAC for Entra ID SSH --------------------------------------
# These live in the root module (not the VM module) because they reference
# specific group object IDs that belong to the calling team/tenant.

data "azuread_group" "linux_admins" {
  display_name = "sg-linux-admins"
}

resource "azurerm_role_assignment" "vm_admin_login" {
  scope                = module.rhel9_app01.id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = data.azuread_group.linux_admins.object_id
}

# --- Outputs the pipeline will hand to AAP -----------------------------------

output "vm_name" {
  value = module.rhel9_app01.name
}

output "vm_private_ip" {
  value = module.rhel9_app01.private_ip_address
}

variable "aap_admin_public_key" {
  type      = string
  sensitive = true
}
