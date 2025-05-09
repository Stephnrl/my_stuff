# outputs.tf

output "gallery_id" {
  description = "The ID of the Shared Image Gallery."
  value       = azurerm_shared_image_gallery.this.id
}

output "gallery_name" {
  description = "The name of the Shared Image Gallery."
  value       = azurerm_shared_image_gallery.this.name
}

output "gallery_resource_group_name" {
  description = "The name of the resource group in which the Shared Image Gallery exists."
  value       = azurerm_shared_image_gallery.this.resource_group_name
}

output "gallery_unique_name" {
  description = "The unique name of the Shared Image Gallery."
  value       = azurerm_shared_image_gallery.this.unique_name
}

output "images" {
  description = "A map of shared images created in the gallery."
  value = {
    for k, v in azurerm_shared_image.this : k => {
      id          = v.id
      name        = v.name
      location    = v.location
      os_type     = v.os_type
      identifier  = v.identifier
      unique_name = v.unique_name
    }
  }
}
