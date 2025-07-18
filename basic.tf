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

# Spoke VPC that routes through Transit Gateway
module "spoke_vpc" {
  source = "../../"

  vpc_name = "${var.environment}-${var.spoke_name}-vpc"
  vpc_cidr = var.spoke_vpc_cidr
  
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  
  # Spoke doesn't need its own internet gateway
  enable_internet_gateway = false
  enable_nat_gateway      = false
  
  # Connect to Transit Gateway
  enable_transit_gateway     = true
  transit_gateway_id         = var.transit_gateway_id
  transit_gateway_route_table_id = var.spoke_route_table_id
  route_internet_through_tgw = true
  auto_accept_shared_attachments = true
  
  # Define networks accessible through TGW
  hub_cidr_blocks = var.hub_cidr_blocks
  
  tags = merge(var.tags, {
    Type = "spoke"
    Spoke = var.spoke_name
  })
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

variable "spoke_name" {
  description = "Name of this spoke (e.g., app, data, etc.)"
  type        = string
  default     = "app"
}

variable "spoke_vpc_cidr" {
  description = "CIDR block for spoke VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-gov-west-1a", "us-gov-west-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks (used as transit subnets)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.1.4.0/24", "10.1.5.0/24"]
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID from hub"
  type        = string
}

variable "spoke_route_table_id" {
  description = "Spoke route table ID from hub"
  type        = string
  default     = ""
}

variable "hub_cidr_blocks" {
  description = "CIDR blocks for hub and other spokes"
  type        = list(string)
  default = [
    "10.0.0.0/16",  # Hub VPC
    "10.2.0.0/16",  # Data spoke
    "192.168.0.0/16" # On-premises
  ]
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Terraform = "true"
    Purpose   = "spoke-example"
  }
}



# Copy this file to terraform.tfvars and customize

aws_region    = "us-gov-west-1"
environment   = "production"
spoke_name    = "application"
spoke_vpc_cidr = "10.1.0.0/16"

# Get these from your hub VPC outputs
transit_gateway_id    = "tgw-1234567890abcdef0"
spoke_route_table_id = "tgw-rtb-1234567890abcdef0"

hub_cidr_blocks = [
  "10.0.0.0/16",    # Hub VPC
  "10.2.0.0/16",    # Data spoke
  "192.168.0.0/16"  # On-premises network
]

tags = {
  Environment = "production"
  Project     = "my-app"
  Owner       = "platform-team"
}
