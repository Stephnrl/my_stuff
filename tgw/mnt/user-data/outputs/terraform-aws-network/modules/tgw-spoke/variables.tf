variable "attachment_name" {
  description = "Name tag for the VPC attachment. Include the account or workload name so it is identifiable from the hub."
  type        = string
}

variable "transit_gateway_id" {
  description = "ID of the shared transit gateway (output transit_gateway_id from tgw-hub)."
  type        = string
}

variable "resource_share_arn" {
  description = "ARN of the RAM share to accept. Required when accept_ram_share is true."
  type        = string
  default     = null
}

variable "accept_ram_share" {
  description = "Accept the RAM invitation. Set false once org-level RAM sharing is enabled, since no invitation is generated."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC to attach."
  type        = string
}

variable "subnet_ids" {
  description = "One subnet per AZ for the attachment ENIs. Use small dedicated /28 TGW subnets, not workload or public subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID is required."
  }
}

variable "appliance_mode_support" {
  description = "Enable appliance mode for flow-symmetric inspection. Required for centralized firewall designs."
  type        = bool
  default     = false
}

variable "dns_support" {
  description = "Enable DNS resolution for the attachment."
  type        = bool
  default     = true
}

variable "ipv6_support" {
  description = "Enable IPv6 support for the attachment."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the attachment. Hub-side automation commonly keys off these."
  type        = map(string)
  default     = {}
}
