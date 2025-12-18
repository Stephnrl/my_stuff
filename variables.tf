variable "openai_account_name" {
  description = "Name of the Azure OpenAI account"
  type        = string
}

variable "location" {
  description = "Azure region for the resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name where OpenAI and private endpoint will be created"
  type        = string
}

variable "sku_name" {
  description = "SKU name for the Azure OpenAI account"
  type        = string
  default     = "S0"
}

variable "custom_subdomain_name" {
  description = "Custom subdomain name for the Azure OpenAI account (must be globally unique)"
  type        = string
}

# Networking variables
variable "vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Resource group name where the VNet is located"
  type        = string
}

variable "subnet_name" {
  description = "Name of the existing subnet for the private endpoint"
  type        = string
}

# DNS variables
variable "private_dns_zone_name" {
  description = "Name of the existing private DNS zone (typically privatelink.openai.azure.com)"
  type        = string
  default     = "privatelink.openai.azure.com"
}

variable "dns_zone_resource_group_name" {
  description = "Resource group name where the private DNS zone is located"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
