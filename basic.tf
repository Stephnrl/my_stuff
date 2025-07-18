terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Transit Gateway for hub-spoke topology
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Hub Transit Gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  
  tags = merge(var.tags, {
    Name = "${var.environment}-hub-tgw"
  })
}

# Hub VPC with internet access
module "hub_vpc" {
  source = "../../"

  vpc_name = "${var.environment}-hub-vpc"
  vpc_cidr = var.hub_vpc_cidr
  
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  
  # Hub needs internet gateway
  enable_internet_gateway = true
  enable_nat_gateway      = true
  single_nat_gateway      = var.single_nat_gateway
  
  # Attach to Transit Gateway
  enable_transit_gateway = true
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  
  # Don't route internet through TGW (hub provides internet)
  route_internet_through_tgw = false
  
  tags = merge(var.tags, {
    Type = "hub"
  })
}

# Route table for spoke VPCs
resource "aws_ec2_transit_gateway_route_table" "spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  
  tags = merge(var.tags, {
    Name = "${var.environment}-spokes-rt"
  })
}

# Default route to hub VPC for internet access
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = module.hub_vpc.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}






variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-gov-west-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "hub_vpc_cidr" {
  description = "CIDR block for hub VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-gov-west-1a", "us-gov-west-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24"]
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Terraform = "true"
    Purpose   = "hub-spoke-example"
  }
}





output "hub_vpc_id" {
  description = "Hub VPC ID"
  value       = module.hub_vpc.vpc_id
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.main.id
}

output "spoke_route_table_id" {
  description = "Route table ID for spoke VPCs"
  value       = aws_ec2_transit_gateway_route_table.spokes.id
}

output "hub_public_subnet_ids" {
  description = "Hub public subnet IDs"
  value       = module.hub_vpc.public_subnet_ids
}

output "hub_private_subnet_ids" {
  description = "Hub private subnet IDs"
  value       = module.hub_vpc.private_subnet_ids
}


