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

  default_tags {
    tags = var.default_tags
  }
}

# Basic VPC with Internet Gateway and NAT Gateways
module "vpc" {
  source = "../../"

  vpc_name = var.vpc_name
  vpc_cidr = var.vpc_cidr
  
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  
  enable_internet_gateway = true
  enable_nat_gateway      = true
  single_nat_gateway      = var.single_nat_gateway
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = var.tags
}





variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-gov-west-1"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "basic-vpc-example"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
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
  description = "Use single NAT Gateway for cost savings"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default = {
    Example     = "basic-vpc"
    Purpose     = "demonstration"
  }
}

variable "default_tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Environment = "example"
  }
}





output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = module.vpc.nat_gateway_ids
}



# Copy this file to terraform.tfvars and customize

aws_region = "us-gov-west-1"
vpc_name   = "my-basic-vpc"
vpc_cidr   = "10.0.0.0/16"

availability_zones = [
  "us-gov-west-1a",
  "us-gov-west-1b"
]

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]

private_subnet_cidrs = [
  "10.0.4.0/24",
  "10.0.5.0/24"
]

# Set to true for cost savings in dev environments
single_nat_gateway = false

tags = {
  Environment = "development"
  Project     = "my-project"
  Owner       = "platform-team"
}
