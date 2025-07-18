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
