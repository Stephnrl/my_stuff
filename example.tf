# Example usage of the Azure Shared Image Gallery module

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "East US"
}

module "shared_image_gallery" {
  source = "../"  # Path to the module

  name                = "exampleimagegallery"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  description         = "Example Shared Image Gallery"
  environment         = "dev"
  
  tags = {
    purpose = "example"
    owner   = "terraform"
  }

  # Optional sharing settings for community gallery
  sharing = {
    permission = "Community"
    community_gallery = {
      prefix          = "example"
      publisher_email = "publisher@example.com"
      publisher_uri   = "https://example.com"
    }
  }

  # Timeouts for operations
  timeouts = {
    create = "60m"
    update = "60m"
    read   = "5m"
    delete = "60m"
  }

  # Define shared images
  shared_image_definitions = {
    "ubuntu-server" = {
      name    = "ubuntu-server"
      os_type = "Linux"
      identifier = {
        publisher = "ExamplePublisher"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
      }
      description              = "Ubuntu Server 18.04 LTS"
      architecture             = "x64"
      hyper_v_generation       = "V1"
      specialized              = false
      max_recommended_vcpu_count = 8
      min_recommended_vcpu_count = 2
      max_recommended_memory_in_gb = 16
      min_recommended_memory_in_gb = 4
      tags = {
        os_type  = "Linux"
        version  = "18.04-LTS"
      }
    },
    "windows-server" = {
      name    = "windows-server"
      os_type = "Windows"
      identifier = {
        publisher = "ExamplePublisher"
        offer     = "WindowsServer"
        sku       = "2019-Datacenter"
      }
      description              = "Windows Server 2019 Datacenter"
      architecture             = "x64"
      hyper_v_generation       = "V1"
      specialized              = false
      max_recommended_vcpu_count = 16
      min_recommended_vcpu_count = 4
      max_recommended_memory_in_gb = 32
      min_recommended_memory_in_gb = 8
      tags = {
        os_type  = "Windows"
        version  = "2019-Datacenter"
      }
    }
  }

  # Optional resource lock
  lock = {
    kind = "CanNotDelete"
    name = "do-not-delete-gallery"
  }

  # Optional role assignments
  role_assignments = {
    "reader" = {
      principal_id               = "00000000-0000-0000-0000-000000000000" # Replace with actual principal ID
      role_definition_id_or_name = "Reader"
    }
  }
}

# Outputs
output "gallery_id" {
  value = module.shared_image_gallery.gallery_id
}

output "images" {
  value = module.shared_image_gallery.images
}
