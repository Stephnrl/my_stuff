# variables.tf
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_internet_gateway" {
  description = "Enable Internet Gateway (set to false for spoke VPCs in hub-spoke topology)"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
  default     = false
}

variable "enable_transit_gateway" {
  description = "Enable Transit Gateway attachment for hub-spoke topology"
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID to attach to (optional if transit_gateway_name is provided)"
  type        = string
  default     = ""
}

variable "transit_gateway_name" {
  description = "Transit Gateway Name to lookup (alternative to transit_gateway_id for cross-account)"
  type        = string
  default     = ""
}

variable "transit_gateway_owner_account_id" {
  description = "AWS Account ID that owns the Transit Gateway (for cross-account attachments)"
  type        = string
  default     = ""
}

variable "transit_gateway_route_table_id" {
  description = "Transit Gateway Route Table ID for association (only works after manual acceptance in hub account)"
  type        = string
  default     = ""
}

variable "auto_accept_shared_attachments" {
  description = "Whether TGW auto-accepts attachments (false for cross-account)"
  type        = bool
  default     = false
}

variable "hub_cidr_blocks" {
  description = "CIDR blocks for hub VPC and other spokes (for routing through TGW)"
  type        = list(string)
  default     = []
}

variable "route_internet_through_tgw" {
  description = "Route internet traffic (0.0.0.0/0) through Transit Gateway instead of IGW"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "spoke-vpc"
}

# main.tf
# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(var.tags, {
    Name = var.vpc_name
  })
}

# Internet Gateway (Optional - typically not used in spoke VPCs)
resource "aws_internet_gateway" "main" {
  count = var.enable_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-igw"
  })
}

# Data source to lookup Transit Gateway by name (for cross-account scenarios)
data "aws_ec2_transit_gateway" "main" {
  count = var.enable_transit_gateway && var.transit_gateway_name != "" ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [var.transit_gateway_name]
  }

  # Optionally filter by owner account ID for cross-account
  dynamic "filter" {
    for_each = var.transit_gateway_owner_account_id != "" ? [1] : []
    content {
      name   = "owner-id"
      values = [var.transit_gateway_owner_account_id]
    }
  }
}

# Local to determine which TGW ID to use
locals {
  transit_gateway_id = var.transit_gateway_id != "" ? var.transit_gateway_id : (
    var.transit_gateway_name != "" ? data.aws_ec2_transit_gateway.main[0].id : ""
  )
}

# Transit Gateway Attachment (For hub-spoke topology)
resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  count = var.enable_transit_gateway ? 1 : 0

  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = local.transit_gateway_id
  vpc_id             = aws_vpc.main.id

  # For cross-account attachments, these will be pending until manually accepted
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-tgw-attachment"
    Note = var.transit_gateway_owner_account_id != "" ? "Cross-account attachment - requires manual acceptance in hub account" : ""
  })

  lifecycle {
    ignore_changes = [
      # Ignore state changes since cross-account attachments remain pending
      tags["Note"]
    ]
  }
}

# Transit Gateway Route Table Association
# Note: This will only work after the attachment is accepted in the hub account
resource "aws_ec2_transit_gateway_route_table_association" "main" {
  count = var.enable_transit_gateway && var.transit_gateway_route_table_id != "" && var.auto_accept_shared_attachments ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.main[0].id
  transit_gateway_route_table_id = var.transit_gateway_route_table_id
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = var.enable_internet_gateway

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-${count.index + 1}"
    Type = var.enable_internet_gateway ? "Public" : "Transit"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-${count.index + 1}"
    Type = "Private"
  })
}

# Elastic IPs for NAT Gateways (only if IGW is enabled)
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway && var.enable_internet_gateway ? (var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)) : 0

  domain = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat-eip-${count.index + 1}"
  })
}

# NAT Gateways (only if IGW is enabled)
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway && var.enable_internet_gateway ? (var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat-${count.index + 1}"
  })
}

# Public/Transit Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Route to Internet Gateway (traditional public route)
  dynamic "route" {
    for_each = var.enable_internet_gateway && !var.route_internet_through_tgw ? [1] : []
    content {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.main[0].id
    }
  }

  # Route internet traffic through Transit Gateway (spoke configuration)
  dynamic "route" {
    for_each = var.enable_transit_gateway && var.route_internet_through_tgw ? [1] : []
    content {
      cidr_block         = "0.0.0.0/0"
      transit_gateway_id = local.transit_gateway_id
    }
  }

  # Routes to hub and other spokes through Transit Gateway
  dynamic "route" {
    for_each = var.enable_transit_gateway ? var.hub_cidr_blocks : []
    content {
      cidr_block         = route.value
      transit_gateway_id = local.transit_gateway_id
    }
  }

  tags = merge(var.tags, {
    Name = var.enable_internet_gateway ? "${var.vpc_name}-public-rt" : "${var.vpc_name}-transit-rt"
  })
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = var.single_nat_gateway && var.enable_nat_gateway ? 1 : length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  # Route to NAT Gateway for internet access (traditional setup)
  dynamic "route" {
    for_each = var.enable_nat_gateway && var.enable_internet_gateway && !var.route_internet_through_tgw ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
    }
  }

  # Route internet traffic through Transit Gateway
  dynamic "route" {
    for_each = var.enable_transit_gateway && var.route_internet_through_tgw ? [1] : []
    content {
      cidr_block         = "0.0.0.0/0"
      transit_gateway_id = local.transit_gateway_id
    }
  }

  # Routes to hub and other spokes through Transit Gateway
  dynamic "route" {
    for_each = var.enable_transit_gateway ? var.hub_cidr_blocks : []
    content {
      cidr_block         = route.value
      transit_gateway_id = local.transit_gateway_id
    }
  }

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-rt-${count.index + 1}"
  })
}

# Public Route Table Association
resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table Association
resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id = aws_subnet.private[count.index].id
  route_table_id = var.single_nat_gateway && var.enable_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}

# VPC Endpoints (Optional)
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_transit_gateway ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-s3-endpoint"
  })
}

# Data source for current region
data "aws_region" "current" {}

# Data source for current account ID
data "aws_caller_identity" "current" {}

# outputs.tf
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = var.enable_internet_gateway ? aws_internet_gateway.main[0].id : null
}

output "transit_gateway_attachment_id" {
  description = "ID of the Transit Gateway VPC Attachment"
  value       = var.enable_transit_gateway ? aws_ec2_transit_gateway_vpc_attachment.main[0].id : null
}

output "transit_gateway_id" {
  description = "ID of the Transit Gateway used"
  value       = var.enable_transit_gateway ? local.transit_gateway_id : null
}

output "transit_gateway_attachment_state" {
  description = "State of the Transit Gateway attachment (will be 'pending' for cross-account until accepted)"
  value       = var.enable_transit_gateway ? aws_ec2_transit_gateway_vpc_attachment.main[0].state : null
}

output "cross_account_acceptance_required" {
  description = "Whether manual acceptance is required in the hub account"
  value       = var.enable_transit_gateway && var.transit_gateway_owner_account_id != ""
}

output "hub_account_acceptance_info" {
  description = "Information for hub account admin to accept the attachment"
  value = var.enable_transit_gateway && var.transit_gateway_owner_account_id != "" ? {
    attachment_id    = aws_ec2_transit_gateway_vpc_attachment.main[0].id
    vpc_id          = aws_vpc.main.id
    vpc_cidr        = aws_vpc.main.cidr_block
    account_id      = data.aws_caller_identity.current.account_id
    attachment_name = "${var.vpc_name}-tgw-attachment"
  } : null
}

output "public_subnet_ids" {
  description = "IDs of the public/transit subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public/transit subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = var.enable_nat_gateway && var.enable_internet_gateway ? aws_nat_gateway.main[*].id : []
}

output "public_route_table_id" {
  description = "ID of the public/transit route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = aws_route_table.private[*].id
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = var.enable_transit_gateway ? aws_vpc_endpoint.s3[0].id : null
}
