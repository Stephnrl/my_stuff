# Example usage of the Azure VM ARM Template module
# This demonstrates deploying a RHEL 9 Gen2 VM with Trusted Launch and network-isolated disks

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {
    template_deployment {
      delete_nested_items_during_deletion = true
    }
  }
}

# Reference existing resources
data "azurerm_resource_group" "example" {
  name = "my-resource-group"
}

data "azurerm_subnet" "example" {
  name                 = "my-subnet"
  virtual_network_name = "my-vnet"
  resource_group_name  = data.azurerm_resource_group.example.name
}

# Reference the Compute Gallery Image created by Packer
data "azurerm_shared_image_version" "rhel9" {
  name                = "1.0.0"  # Your image version
  image_name          = "rhel9-gen2-trusted"  # Your image definition name
  gallery_name        = "myGallery"  # Your gallery name
  resource_group_name = "gallery-rg"  # Gallery resource group
}

# Deploy the VM using the ARM template module
module "rhel_vm" {
  source = "../"  # Path to the module
  
  # Required parameters
  resource_group_name       = data.azurerm_resource_group.example.name
  vm_name                   = "rhel9-vm-001"
  location                  = data.azurerm_resource_group.example.location
  subnet_id                 = data.azurerm_subnet.example.id
  compute_gallery_image_id  = data.azurerm_shared_image_version.rhel9.id
  
  # VM configuration
  vm_size                   = "Standard_D4s_v5"  # Must support Gen2 and Trusted Launch
  admin_username            = "azureuser"
  ssh_public_key            = file("~/.ssh/id_rsa.pub")  # Or use admin_password
  
  # OS disk configuration (with network isolation)
  os_disk_size_gb          = 128
  os_disk_type             = "Premium_LRS"
  
  # Data disks (also with network isolation)
  data_disks = [
    {
      name               = "data1"
      diskSizeGB        = 256
      lun               = 0
      storageAccountType = "Premium_LRS"
    },
    {
      name               = "apps"
      diskSizeGB        = 512
      lun               = 1
      storageAccountType = "StandardSSD_LRS"
    }
  ]
  
  # Networking
  enable_accelerated_networking = true
  use_public_ip                = false  # No public IP for security
  
  # Availability
  availability_zone = "1"  # Optional: specify zone for the VM
  
  # Tags
  tags = {
    Environment = "Production"
    OS          = "RHEL9"
    ManagedBy   = "Terraform"
    Generation  = "Gen2"
    Security    = "TrustedLaunch"
  }
}

# Outputs
output "vm_id" {
  value = module.rhel_vm.vm_id
}

output "private_ip" {
  value = module.rhel_vm.private_ip_address
}

output "os_disk_id" {
  value = module.rhel_vm.os_disk_id
}

# Optional: Create additional network security rules or attach to backup policies
resource "azurerm_network_security_rule" "ssh_internal" {
  name                        = "AllowSSHInternal"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "10.0.0.0/8"  # Internal network only
  destination_address_prefix = module.rhel_vm.private_ip_address
  resource_group_name        = data.azurerm_resource_group.example.name
  network_security_group_name = "my-nsg"  # Your existing NSG
}
