variable "name" {
  description = "Name tag for the transit gateway."
  type        = string
}

variable "description" {
  description = "Description applied to the transit gateway."
  type        = string
  default     = "Landing zone hub transit gateway"
}

variable "amazon_side_asn" {
  description = "Private ASN for the Amazon side of a BGP session. Immutable after creation."
  type        = number
  default     = 64512
}

variable "auto_accept_shared_attachments" {
  description = "Automatically accept cross-account attachment requests. When false the hub must run tgw-routing with accept_attachment = true for each spoke."
  type        = bool
  default     = false
}

variable "default_route_table_association" {
  description = "Associate new attachments with the default route table (flat topology)."
  type        = bool
  default     = true
}

variable "default_route_table_propagation" {
  description = "Propagate new attachment routes into the default route table (flat topology)."
  type        = bool
  default     = true
}

variable "dns_support" {
  description = "Enable DNS resolution across attachments."
  type        = bool
  default     = true
}

variable "vpn_ecmp_support" {
  description = "Enable ECMP across VPN attachments."
  type        = bool
  default     = true
}

variable "transit_gateway_cidr_blocks" {
  description = "Optional CIDR blocks for the transit gateway (Connect / VPN client use cases)."
  type        = list(string)
  default     = null
}

variable "route_tables" {
  description = <<-EOT
    Segmentation route tables to create, keyed by name. Leave empty for a flat
    topology. When populated you almost certainly want
    default_route_table_association and default_route_table_propagation false.

    Example:
      { workloads = {}, inspection = {}, shared-services = { tags = { Tier = "core" } } }
  EOT
  type = map(object({
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "share_name" {
  description = "Name of the RAM resource share."
  type        = string
}

variable "allow_external_principals" {
  description = "Allow principals outside this AWS Organization. Keep false for a same-org landing zone."
  type        = bool
  default     = false
}

variable "permission_arns" {
  description = "Optional RAM permission ARNs. Null uses the AWS-managed default for transit gateways."
  type        = list(string)
  default     = null
}

variable "shared_principals" {
  description = "Account IDs (invitation flow) or OU / Organization ARNs (org-sharing flow) to share the transit gateway with."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for p in var.shared_principals :
      can(regex("^[0-9]{12}$", p)) || can(regex("^arn:aws[a-z-]*:organizations::", p))
    ])
    error_message = "Each principal must be a 12-digit account ID or an AWS Organizations ARN."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
