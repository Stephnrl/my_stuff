################################################################################
# VPC
################################################################################

variable "create_vpc" {
  description = "Controls if VPC should be created (it affects almost all resources)"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
  default     = ""
}

variable "cidr" {
  description = "The IPv4 CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_tenancy" {
  description = "A tenancy option for instances launched into the VPC"
  type        = string
  default     = "default"
}

variable "enable_dns_hostnames" {
  description = "Should be true to enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Should be true to enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "assign_generated_ipv6_cidr_block" {
  description = "Requests an Amazon-provided IPv6 CIDR block with a /56 prefix length for the VPC"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "vpc_tags" {
  description = "Additional tags for the VPC"
  type        = map(string)
  default     = {}
}

################################################################################
# Availability Zones
################################################################################

variable "azs" {
  description = "A list of availability zones names or ids in the region"
  type        = list(string)
  default     = []
}

################################################################################
# Subnets
################################################################################

variable "private_subnets" {
  description = "A list of private subnets inside the VPC"
  type        = list(string)
  default     = null
}

variable "public_subnets" {
  description = "A list of public subnets inside the VPC"
  type        = list(string)
  default     = null
}

variable "create_public_subnets" {
  description = "Controls if public subnets should be created (set to false for internal-only hub-spoke)"
  type        = bool
  default     = false
}

variable "private_subnet_assign_ipv6_address_on_creation" {
  description = "Assign IPv6 address on private subnet, must be disabled to change IPv6 CIDRs"
  type        = bool
  default     = false
}

variable "map_public_ip_on_launch" {
  description = "Should be false if you do not want to auto-assign public IP on launch"
  type        = bool
  default     = true
}

variable "private_subnet_tags" {
  description = "Additional tags for the private subnets"
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Additional tags for the public subnets"
  type        = map(string)
  default     = {}
}

################################################################################
# Internet Gateway
################################################################################

variable "enable_internet_gateway" {
  description = "Should be true to enable internet gateway (typically false for hub-spoke)"
  type        = bool
  default     = false
}

variable "igw_tags" {
  description = "Additional tags for the internet gateway"
  type        = map(string)
  default     = {}
}

################################################################################
# NAT Gateway
################################################################################

variable "enable_nat_gateway" {
  description = "Should be true if you want to provision NAT Gateways for each of your private networks"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway across all of your private networks"
  type        = bool
  default     = true
}

variable "nat_eip_tags" {
  description = "Additional tags for the NAT EIP"
  type        = map(string)
  default     = {}
}

variable "nat_gateway_tags" {
  description = "Additional tags for the NAT gateways"
  type        = map(string)
  default     = {}
}

################################################################################
# Route Tables
################################################################################

variable "public_route_table_tags" {
  description = "Additional tags for the public route tables"
  type        = map(string)
  default     = {}
}

variable "private_route_table_tags" {
  description = "Additional tags for the private route tables"
  type        = map(string)
  default     = {}
}

################################################################################
# Transit Gateway
################################################################################

variable "create_tgw_attachment" {
  description = "Controls if Transit Gateway VPC attachment should be created"
  type        = bool
  default     = true
}

variable "transit_gateway_id" {
  description = "The ID of the Transit Gateway (from hub account)"
  type        = string
  default     = ""
}

variable "tgw_route_destinations" {
  description = "List of destination CIDR blocks to route through Transit Gateway"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "tgw_dns_support" {
  description = "Whether DNS support is enabled for the Transit Gateway attachment"
  type        = string
  default     = "enable"
}

variable "tgw_ipv6_support" {
  description = "Whether IPv6 support is enabled for the Transit Gateway attachment"
  type        = string
  default     = "disable"
}

variable "tgw_default_route_table_association" {
  description = "Whether the VPC attachment should be associated with the default route table"
  type        = string
  default     = "enable"
}

variable "tgw_default_route_table_propagation" {
  description = "Whether the VPC attachment should propagate routes to the default route table"
  type        = string
  default     = "enable"
}

variable "tgw_attachment_tags" {
  description = "Additional tags for the Transit Gateway VPC attachment"
  type        = map(string)
  default     = {}
}

################################################################################
# Default Security Group
################################################################################

variable "manage_default_security_group" {
  description = "Should be true to adopt and manage default security group"
  type        = bool
  default     = true
}

variable "default_security_group_name" {
  description = "Name to be used on the default security group"
  type        = string
  default     = null
}

variable "default_security_group_ingress" {
  description = "List of maps of ingress rules to set on the default security group"
  type        = list(map(string))
  default = [
    {
      description = "Allow all traffic from VPC"
      self        = true
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
    }
  ]
}

variable "default_security_group_egress" {
  description = "List of maps of egress rules to set on the default security group"
  type        = list(map(string))
  default = [
    {
      description = "Allow all outbound traffic"
      cidr_blocks = "0.0.0.0/0"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
    }
  ]
}

variable "default_security_group_tags" {
  description = "Additional tags for the default security group"
  type        = map(string)
  default     = {}
}
