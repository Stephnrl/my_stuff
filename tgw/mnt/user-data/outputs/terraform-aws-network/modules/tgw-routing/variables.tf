variable "attachment_name" {
  description = "Name tag applied by the hub when accepting the attachment."
  type        = string
}

variable "transit_gateway_attachment_id" {
  description = "Attachment ID created by the spoke (attachment_id output of tgw-spoke)."
  type        = string
}

variable "accept_attachment" {
  description = "Accept a pending attachment. Set true when the TGW has auto_accept_shared_attachments disabled."
  type        = bool
  default     = true
}

variable "associate_route_table_id" {
  description = "Route table to associate the attachment with. Null skips association (flat topology)."
  type        = string
  default     = null
}

variable "propagate_to_route_table_ids" {
  description = "Route tables that should learn this attachment's routes."
  type        = set(string)
  default     = []
}

variable "static_routes" {
  description = <<-EOT
    Static routes pointing at this attachment, keyed by an arbitrary name.

    Example:
      default_egress = {
        destination_cidr_block = "0.0.0.0/0"
        route_table_id         = module.hub.route_table_ids["workloads"]
      }
  EOT
  type = map(object({
    destination_cidr_block = string
    route_table_id         = string
    blackhole              = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to the accepted attachment."
  type        = map(string)
  default     = {}
}
