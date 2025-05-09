# variables.tf

variable "name" {
  description = "The name of the Shared Image Gallery."
  type        = string
}

variable "location" {
  description = "The Azure region where the resource should exist."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group in which to create the Shared Image Gallery."
  type        = string
}

variable "description" {
  description = "The description of the Shared Image Gallery."
  type        = string
  default     = null
}

variable "tags" {
  description = "A mapping of tags to assign to the Shared Image Gallery."
  type        = map(string)
  default     = {}
}

variable "sharing" {
  description = "Sharing profile for the gallery."
  type = object({
    permission = string
    community_gallery = optional(object({
      eula            = optional(string)
      prefix          = string
      publisher_email = string
      publisher_uri   = string
    }))
  })
  default = null
}

variable "timeouts" {
  description = "Timeouts for operations."
  type = object({
    create = optional(string)
    delete = optional(string)
    read   = optional(string)
    update = optional(string)
  })
  default = null
}

variable "shared_image_definitions" {
  description = "Map of shared image definitions to create in the gallery."
  type = map(object({
    name                = string
    os_type             = string
    identifier = object({
      offer     = string
      publisher = string
      sku       = string
    })
    accelerated_network_support_enabled = optional(bool)
    architecture                        = optional(string)
    confidential_vm_enabled             = optional(bool)
    confidential_vm_supported           = optional(bool)
    description                         = optional(string)
    disk_types_not_allowed              = optional(list(string))
    end_of_life_date                    = optional(string)
    eula                                = optional(string)
    hyper_v_generation                  = optional(string)
    max_recommended_memory_in_gb        = optional(number)
    max_recommended_vcpu_count          = optional(number)
    min_recommended_memory_in_gb        = optional(number)
    min_recommended_vcpu_count          = optional(number)
    privacy_statement_uri               = optional(string)
    release_note_uri                    = optional(string)
    specialized                         = optional(bool)
    trusted_launch_enabled              = optional(bool)
    trusted_launch_supported            = optional(bool)
    tags                                = optional(map(string))
    purchase_plan = optional(object({
      name      = string
      product   = string
      publisher = string
    }))
  }))
  default = {}
}

variable "lock" {
  description = "The lock level to apply to the Shared Image Gallery. Default is `None`. Possible values are `None`, `CanNotDelete`, and `ReadOnly`."
  type = object({
    kind = string
    name = optional(string)
  })
  default = null
}

variable "role_assignments" {
  description = "A map of role assignments to create on the Shared Image Gallery."
  type = map(object({
    principal_id                           = string
    role_definition_id_or_name             = string
    condition                              = optional(string)
    condition_version                      = optional(string)
    delegated_managed_identity_resource_id = optional(string)
    skip_service_principal_aad_check       = optional(bool)
  }))
  default = {}
}
