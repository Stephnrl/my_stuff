# Azure Authentication Variables
variable "client_id" {
  type        = string
  description = "Azure Service Principal Client ID"
  default     = env("ARM_CLIENT_ID")
}

variable "tenant_id" {
  type        = string
  description = "Azure Tenant ID"
  default     = env("ARM_TENANT_ID")
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
  default     = env("ARM_SUBSCRIPTION_ID")
}

# Resource Group and Gallery Variables
variable "resource_group_name" {
  type        = string
  description = "Resource group for Compute Gallery"
}

variable "gallery_name" {
  type        = string
  description = "Azure Compute Gallery name"
}

variable "gallery_resource_group" {
  type        = string
  description = "Resource group containing the gallery"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "eastus2"
}

variable "replication_regions" {
  type        = list(string)
  description = "Regions to replicate the image"
  default     = ["eastus2", "westus2", "centralus"]
}

# Build Variables
variable "build_resource_group_name" {
  type        = string
  description = "Temporary resource group for building"
  default     = "packer-build-rg"
}

variable "vm_size" {
  type        = string
  description = "VM size for building"
  default     = "Standard_D2s_v3"
}

# Tagging
variable "tags" {
  type = map(string)
  default = {
    "ManagedBy"   = "Packer"
    "Environment" = "Production"
    "BuildDate"   = "{{ timestamp }}"
  }
}

# Network
variable "virtual_network_name" {
  type        = string
  description = "Virtual network for build VM"
  default     = ""
}

variable "virtual_network_subnet_name" {
  type        = string
  description = "Subnet for build VM"
  default     = ""
}

variable "virtual_network_resource_group_name" {
  type        = string
  description = "Resource group of the virtual network"
  default     = ""
}
