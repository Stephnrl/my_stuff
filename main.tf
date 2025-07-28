################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

################################################################################
# Local Values
################################################################################

locals {
  create_vpc = var.create_vpc
  create_tgw_attachment = var.create_tgw_attachment && local.create_vpc
  
  # Calculate subnets automatically if not provided
  private_subnets = var.private_subnets != null ? var.private_subnets : [
    for k, v in var.azs : cidrsubnet(var.cidr, 8, k)
  ]
  
  public_subnets = var.create_public_subnets && var.public_subnets != null ? var.public_subnets : (
    var.create_public_subnets ? [
      for k, v in var.azs : cidrsubnet(var.cidr, 8, k + 100)
    ] : []
  )
  
  # For hub-spoke, we typically route through TGW instead of IGW
  enable_internet_gateway = var.create_public_subnets && var.enable_internet_gateway
  enable_nat_gateway = var.create_public_subnets && var.enable_nat_gateway
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  count = local.create_vpc ? 1 : 0

  cidr_block                       = var.cidr
  instance_tenancy                 = var.instance_tenancy
  enable_dns_hostnames             = var.enable_dns_hostnames
  enable_dns_support               = var.enable_dns_support
  assign_generated_ipv6_cidr_block = var.assign_generated_ipv6_cidr_block

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.vpc_tags,
  )
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  count = local.create_vpc && local.enable_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(
    { "Name" = "${var.name}-igw" },
    var.tags,
    var.igw_tags,
  )
}

################################################################################
# Private Subnets
################################################################################

resource "aws_subnet" "private" {
  count = local.create_vpc && length(local.private_subnets) > 0 ? length(local.private_subnets) : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = element(local.private_subnets, count.index)
  availability_zone = element(var.azs, count.index)

  assign_ipv6_address_on_creation = var.private_subnet_assign_ipv6_address_on_creation

  tags = merge(
    {
      "Name" = "${var.name}-private-${element(var.azs, count.index)}"
      "Type" = "private"
    },
    var.tags,
    var.private_subnet_tags,
  )
}

################################################################################
# Public Subnets (Optional for hub-spoke)
################################################################################

resource "aws_subnet" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 ? length(local.public_subnets) : 0

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = element(local.public_subnets, count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    {
      "Name" = "${var.name}-public-${element(var.azs, count.index)}"
      "Type" = "public"
    },
    var.tags,
    var.public_subnet_tags,
  )
}

################################################################################
# NAT Gateway (Optional for hub-spoke)
################################################################################

resource "aws_eip" "nat" {
  count = local.create_vpc && local.enable_nat_gateway ? var.single_nat_gateway ? 1 : length(local.public_subnets) : 0

  domain = "vpc"

  tags = merge(
    {
      "Name" = "${var.name}-nat-${var.single_nat_gateway ? "single" : element(var.azs, count.index)}"
    },
    var.tags,
    var.nat_eip_tags,
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.create_vpc && local.enable_nat_gateway ? var.single_nat_gateway ? 1 : length(local.public_subnets) : 0

  allocation_id = element(aws_eip.nat[*].id, var.single_nat_gateway ? 0 : count.index)
  subnet_id     = element(aws_subnet.public[*].id, var.single_nat_gateway ? 0 : count.index)

  tags = merge(
    {
      "Name" = "${var.name}-nat-${var.single_nat_gateway ? "single" : element(var.azs, count.index)}"
    },
    var.tags,
    var.nat_gateway_tags,
  )

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Route Tables
################################################################################

# Public Route Table
resource "aws_route_table" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(
    { "Name" = "${var.name}-public" },
    var.tags,
    var.public_route_table_tags,
  )
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = local.create_vpc && length(local.private_subnets) > 0 ? var.single_nat_gateway ? 1 : length(local.private_subnets) : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(
    {
      "Name" = var.single_nat_gateway ? "${var.name}-private" : "${var.name}-private-${element(var.azs, count.index)}"
    },
    var.tags,
    var.private_route_table_tags,
  )
}

################################################################################
# Routes
################################################################################

# Public Routes
resource "aws_route" "public_internet_gateway" {
  count = local.create_vpc && local.enable_internet_gateway && length(local.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

# Private Routes - NAT Gateway (if public subnets exist)
resource "aws_route" "private_nat_gateway" {
  count = local.create_vpc && local.enable_nat_gateway && length(local.private_subnets) > 0 ? var.single_nat_gateway ? 1 : length(local.private_subnets) : 0

  route_table_id         = element(aws_route_table.private[*].id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, var.single_nat_gateway ? 0 : count.index)

  timeouts {
    create = "5m"
  }
}

# Private Routes - Transit Gateway (for hub-spoke communication)
resource "aws_route" "private_tgw" {
  count = local.create_vpc && local.create_tgw_attachment && length(var.tgw_route_destinations) > 0 ? length(var.tgw_route_destinations) * (var.single_nat_gateway ? 1 : length(local.private_subnets)) : 0

  route_table_id         = element(aws_route_table.private[*].id, count.index % (var.single_nat_gateway ? 1 : length(local.private_subnets)))
  destination_cidr_block = var.tgw_route_destinations[count.index / (var.single_nat_gateway ? 1 : length(local.private_subnets))]
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]

  timeouts {
    create = "5m"
  }
}

################################################################################
# Route Table Associations
################################################################################

resource "aws_route_table_association" "private" {
  count = local.create_vpc && length(local.private_subnets) > 0 ? length(local.private_subnets) : 0

  subnet_id      = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(aws_route_table.private[*].id, var.single_nat_gateway ? 0 : count.index)
}

resource "aws_route_table_association" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 ? length(local.public_subnets) : 0

  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public[0].id
}

################################################################################
# Transit Gateway VPC Attachment (Spoke Side)
################################################################################

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = local.create_tgw_attachment ? 1 : 0

  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this[0].id

  # Enable DNS support for cross-VPC communication
  dns_support  = var.tgw_dns_support
  ipv6_support = var.tgw_ipv6_support

  # Cross-account sharing
  transit_gateway_default_route_table_association = var.tgw_default_route_table_association
  transit_gateway_default_route_table_propagation = var.tgw_default_route_table_propagation

  tags = merge(
    {
      "Name" = "${var.name}-tgw-attachment"
      "Type" = "spoke"
    },
    var.tags,
    var.tgw_attachment_tags,
  )
}

################################################################################
# Default Security Group
################################################################################

resource "aws_default_security_group" "this" {
  count = local.create_vpc && var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  dynamic "ingress" {
    for_each = var.default_security_group_ingress
    content {
      self             = lookup(ingress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(ingress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(ingress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(ingress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(ingress.value, "security_groups", "")))
      description      = lookup(ingress.value, "description", null)
      from_port        = lookup(ingress.value, "from_port", 0)
      to_port          = lookup(ingress.value, "to_port", 0)
      protocol         = lookup(ingress.value, "protocol", "-1")
    }
  }

  dynamic "egress" {
    for_each = var.default_security_group_egress
    content {
      self             = lookup(egress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(egress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(egress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(egress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(egress.value, "security_groups", "")))
      description      = lookup(egress.value, "description", null)
      from_port        = lookup(egress.value, "from_port", 0)
      to_port          = lookup(egress.value, "to_port", 0)
      protocol         = lookup(egress.value, "protocol", "-1")
    }
  }

  tags = merge(
    { "Name" = coalesce(var.default_security_group_name, "${var.name}-default") },
    var.tags,
    var.default_security_group_tags,
  )
}
