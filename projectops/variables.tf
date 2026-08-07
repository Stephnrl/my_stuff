variable "name" {
  description = "Base name for the Azure OpenAI resource. Must be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,60}$", var.name))
    error_message = "Lowercase alphanumerics and hyphens only, 2-60 characters."
  }
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  description = "Region. Model availability varies significantly by region -- confirm your model is offered here before applying."
  type        = string
}

variable "model_name" {
  description = "Azure OpenAI model to deploy. Must support tool calling and structured outputs."
  type        = string
  default     = "gpt-4o"
}

variable "model_version" {
  description = "Model version. Structured outputs need 2024-08-06 or later for gpt-4o."
  type        = string
  default     = "2024-08-06"
}

variable "deployment_name" {
  description = "Deployment name. This is what AZURE_OPENAI_DEPLOYMENT must be set to -- it is NOT the model name."
  type        = string
  default     = "projectops"
}

variable "sku_name" {
  description = "Deployment SKU. GlobalStandard has the widest model availability; DataZoneStandard keeps inference within a geography for residency requirements."
  type        = string
  default     = "GlobalStandard"

  validation {
    condition = contains(
      ["Standard", "GlobalStandard", "DataZoneStandard", "ProvisionedManaged"],
      var.sku_name
    )
    error_message = "Unsupported SKU."
  }
}

variable "capacity" {
  description = "Throughput in thousands of tokens per minute. Issue triage is low volume; 10 is generous."
  type        = number
  default     = 10
}

variable "disable_local_auth" {
  description = "Disable API-key authentication entirely, forcing Entra ID. Recommended: there is then no key to leak, store, or rotate."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Set false when using a private endpoint. Self-hosted runners must then reach the resource over your virtual network."
  type        = bool
  default     = false
}

variable "allowed_ip_rules" {
  description = "Public IP CIDRs permitted when public access is enabled. Ignored entirely when it is not."
  type        = list(string)
  default     = []
}

variable "runner_principal_ids" {
  description = "Object IDs of the managed identities your self-hosted runners use. Each is granted 'Cognitive Services OpenAI User' -- inference only, no management-plane rights."
  type        = list(string)
  default     = []
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the private endpoint. Null disables private networking."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs for privatelink.openai.azure.com. Without these the endpoint resolves to the public name and the whole exercise is pointless."
  type        = list(string)
  default     = []
}

variable "key_vault_id" {
  description = "Key Vault to store the API key in. Ignored when disable_local_auth is true, since there is no key."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
