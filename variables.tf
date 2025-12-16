#------------------------------------------------------------------------------
# General Variables
#------------------------------------------------------------------------------
variable "create_resource_group" {
  description = "Whether to create a new resource group"
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# VNet Variables
#------------------------------------------------------------------------------
variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
}

variable "dns_servers" {
  description = "Custom DNS servers for the VNet"
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Subnet Variables
#------------------------------------------------------------------------------
variable "gateway_subnet_prefix" {
  description = "Address prefix for the Gateway subnet"
  type        = string
  default     = null
}

variable "private_endpoint_subnet_name" {
  description = "Name of the private endpoint subnet"
  type        = string
  default     = "snet-private-endpoints"
}

variable "private_endpoint_subnet_prefix" {
  description = "Address prefix for the private endpoint subnet"
  type        = string
}

variable "workload_subnets" {
  description = "Map of workload subnets to create"
  type = map(object({
    address_prefix    = string
    service_endpoints = optional(list(string), [])
    delegation = optional(object({
      name                    = string
      service_delegation_name = string
      actions                 = optional(list(string))
    }))
  }))
  default = {}
}

#------------------------------------------------------------------------------
# Route Table Variables
#------------------------------------------------------------------------------
variable "enable_bgp_route_propagation" {
  description = "Enable BGP route propagation"
  type        = bool
  default     = false
}

variable "palo_alto_next_hop_ip" {
  description = "IP address of Palo Alto for default route"
  type        = string
  default     = null
}

variable "dns_whitelist_ips" {
  description = "DNS server IPs to whitelist"
  type        = list(string)
  default     = []
}

variable "dns_route_next_hop_type" {
  description = "Next hop type for DNS routes"
  type        = string
  default     = "VnetLocal"
}

variable "dns_route_next_hop_ip" {
  description = "Next hop IP for DNS routes"
  type        = string
  default     = null
}

variable "allow_azure_dns" {
  description = "Allow Azure DNS for Private DNS resolution"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# VPN Gateway Variables
#------------------------------------------------------------------------------
variable "create_vpn_gateway" {
  description = "Whether to create a VPN Gateway"
  type        = bool
  default     = false
}

variable "vpn_gateway_type" {
  description = "Type of VPN Gateway"
  type        = string
  default     = "Vpn"
}

variable "vpn_type" {
  description = "VPN type"
  type        = string
  default     = "RouteBased"
}

variable "vpn_gateway_sku" {
  description = "SKU of the VPN Gateway"
  type        = string
  default     = "VpnGw1AZ"
}

variable "vpn_gateway_active_active" {
  description = "Enable active-active mode"
  type        = bool
  default     = false
}

variable "vpn_gateway_enable_bgp" {
  description = "Enable BGP for VPN Gateway"
  type        = bool
  default     = false
}

variable "vpn_gateway_bgp_asn" {
  description = "BGP ASN for VPN Gateway"
  type        = number
  default     = 65515
}

#------------------------------------------------------------------------------
# Private DNS Variables
#------------------------------------------------------------------------------
variable "private_dns_zones" {
  description = "List of private DNS zones to create"
  type        = list(string)
  default = [
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.database.windows.net"
  ]
}

variable "auto_registration_dns_zone" {
  description = "DNS zone for auto-registration"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Palo Alto Peering Variables
#------------------------------------------------------------------------------
variable "palo_alto_vnet_name" {
  description = "Name of the Palo Alto VNet"
  type        = string
  default     = null
}

variable "palo_alto_resource_group" {
  description = "Resource group of the Palo Alto VNet"
  type        = string
  default     = null
}

variable "allow_gateway_transit" {
  description = "Allow gateway transit"
  type        = bool
  default     = false
}

variable "use_remote_gateway" {
  description = "Use remote gateway"
  type        = bool
  default     = false
}

variable "create_reverse_peering" {
  description = "Create reverse peering from Palo Alto to this VNet"
  type        = bool
  default     = true
}
