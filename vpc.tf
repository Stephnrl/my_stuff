# Example: Hub-Spoke VPC Module Usage
# This shows how to deploy the spoke VPC and handle cross-account TGW attachment

################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

################################################################################
# Local Values
################################################################################

locals {
  name   = "spoke-vpc-${random_string.suffix.result}"
  region = "us-west-2"
  
  # Hub account Transit Gateway ID (shared from hub account)
  hub_tgw_id = "tgw-1234567890abcdef0"  # Replace with actual TGW ID from hub
  
  # CIDR for this spoke VPC
  vpc_cidr = "10.1.0.0/16"
  
  # Get first 3 AZs
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
  
  common_tags = {
    Environment = "prod"
    Project     = "hub-spoke-network"
    ManagedBy   = "terraform"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

################################################################################
# Spoke VPC Module
################################################################################

module "spoke_vpc" {
  source = "./vpc-hub-spoke-module"  # Path to your module

  # VPC Configuration
  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  # Subnet Configuration
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  
  # For internal-only hub-spoke, typically no public subnets
  create_public_subnets = false
  enable_internet_gateway = false
  enable_nat_gateway = false

  # Transit Gateway Configuration
  create_tgw_attachment = true
  transit_gateway_id = local.hub_tgw_id
  
  # Route all RFC 1918 traffic through TGW for hub-spoke communication
  tgw_route_destinations = [
    "10.0.0.0/8",     # Hub and other spokes
    "172.16.0.0/12",  # Additional private networks
    "192.168.0.0/16", # Additional private networks
  ]

  # DNS settings for cross-VPC resolution
  enable_dns_hostnames = true
  enable_dns_support   = true
  tgw_dns_support      = "enable"

  # Default security group - allow communication within VPC and hub-spoke network
  manage_default_security_group = true
  default_security_group_ingress = [
    {
      description = "All traffic from VPC"
      self        = true
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
    },
    {
      description = "All traffic from hub-spoke network"
      cidr_blocks = "10.0.0.0/8"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
    }
  ]

  tags = local.common_tags
}

################################################################################
# Cross-Account TGW Attachment Acceptance (Run in Hub Account)
################################################################################

# This resource should be deployed in the HUB account to accept the attachment
# You can either run this manually or use a separate Terraform configuration
# in the hub account that watches for pending attachments

/*
# Deploy this in the HUB account
resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "spoke_attachment" {
  # This should match the attachment ID from the spoke account
  transit_gateway_attachment_id = module.spoke_vpc.tgw_attachment_id
  
  tags = {
    Name = "spoke-${local.name}-attachment"
    Side = "Hub"
  }
}

# Optional: Create route table entries in hub for this spoke
resource "aws_ec2_transit_gateway_route_table" "spoke_routes" {
  transit_gateway_id = local.hub_tgw_id
  
  tags = {
    Name = "spoke-${local.name}-routes"
  }
}

resource "aws_ec2_transit_gateway_route" "spoke_to_hub" {
  destination_cidr_block         = local.vpc_cidr
  transit_gateway_attachment_id  = module.spoke_vpc.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_routes.id
}
*/

################################################################################
# Optional: Public Subnets for Specific Use Cases
################################################################################

# If you need public subnets for specific resources (like ALB, bastion, etc.)
module "spoke_vpc_with_public" {
  source = "./vpc-hub-spoke-module"

  name = "${local.name}-public"
  cidr = "10.2.0.0/16"
  azs  = local.azs

  # Include both private and public subnets
  private_subnets = [for k, v in local.azs : cidrsubnet("10.2.0.0/16", 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet("10.2.0.0/16", 8, k + 100)]
  
  create_public_subnets   = true
  enable_internet_gateway = true
  enable_nat_gateway      = true
  single_nat_gateway      = true

  # Still connect to TGW for hub-spoke communication
  create_tgw_attachment = true
  transit_gateway_id    = local.hub_tgw_id
  tgw_route_destinations = [
    "10.0.0.0/8",
    "172.16.0.0/12",
  ]

  tags = merge(local.common_tags, {
    Type = "hybrid-public-private"
  })
}

################################################################################
# Outputs
################################################################################

output "spoke_vpc_id" {
  description = "ID of the spoke VPC"
  value       = module.spoke_vpc.vpc_id
}

output "spoke_private_subnets" {
  description = "Private subnet IDs in spoke VPC"
  value       = module.spoke_vpc.private_subnets
}

output "tgw_attachment_id" {
  description = "Transit Gateway attachment ID (needs acceptance in hub account)"
  value       = module.spoke_vpc.tgw_attachment_id
}

output "tgw_attachment_state" {
  description = "State of the TGW attachment"
  value       = module.spoke_vpc.tgw_attachment_state
}

# Output for hub account to know what to accept
output "hub_account_commands" {
  description = "Commands to run in hub account to accept attachment"
  value = <<-EOT
    # Run these commands in the HUB account:
    
    # Accept the attachment:
    aws ec2 accept-transit-gateway-vpc-attachment \
      --transit-gateway-attachment-id ${module.spoke_vpc.tgw_attachment_id} \
      --region ${local.region}
    
    # Or use Terraform in hub account:
    # resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "spoke_${replace(local.name, "-", "_")}" {
    #   transit_gateway_attachment_id = "${module.spoke_vpc.tgw_attachment_id}"
    # }
  EOT
}
