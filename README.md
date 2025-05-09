# Azure Shared Image Gallery Terraform Module

This Terraform module creates an Azure Shared Image Gallery and shared image definitions within the gallery. It follows best practices and includes support for management locks and role assignments.

## Features

- Create an Azure Shared Image Gallery
- Define multiple shared images with customizable properties
- Support for community gallery sharing
- Management lock capabilities
- Role assignment support
- Configurable timeouts
- Comprehensive tagging

## Usage

```hcl
module "shared_image_gallery" {
  source = "path/to/module"

  name                = "exampleimagegallery"
  location            = "East US"
  resource_group_name = "example-rg"
  description         = "Example Shared Image Gallery"
  environment         = "dev"
  
  tags = {
    purpose = "example"
    owner   = "terraform"
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
    }
  }
}
```

See the `example` directory for a complete working example.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| azurerm | >= 3.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the Shared Image Gallery | `string` | n/a | yes |
| location | The Azure region where the resource should exist | `string` | n/a | yes |
| resource_group_name | The name of the resource group in which to create the Shared Image Gallery | `string` | n/a | yes |
| description | The description of the Shared Image Gallery | `string` | `null` | no |
| environment | Environment name to be used in default tags | `string` | `"dev"` | no |
| tags | A mapping of tags to assign to the Shared Image Gallery | `map(string)` | `{}` | no |
| sharing | Sharing profile for the gallery | `object` | `null` | no |
| timeouts | Timeouts for operations | `object` | `null` | no |
| shared_image_definitions | Map of shared image definitions to create in the gallery | `map(object)` | `{}` | no |
| lock | The lock level to apply to the Shared Image Gallery | `object` | `null` | no |
| role_assignments | A map of role assignments to create on the Shared Image Gallery | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| gallery_id | The ID of the Shared Image Gallery |
| gallery_name | The name of the Shared Image Gallery |
| gallery_resource_group_name | The name of the resource group in which the Shared Image Gallery exists |
| gallery_unique_name | The unique name of the Shared Image Gallery |
| images | A map of shared images created in the gallery |

## Notes

- This module supports migration from existing resources using the `moved` blocks
- All shared image attributes have sensible defaults where applicable

## License

MIT
