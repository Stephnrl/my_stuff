###############################################################################
# Root module for a member/workload account.
# One state file per account. This is the file account vending stamps out.
###############################################################################

terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket       = "acme-tfstate-network"
    key          = "spokes/workload-prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${var.spoke_account_id}:role/TerraformExecution"
    session_name = "gha-spoke"
  }
}

# Read hub outputs rather than hardcoding IDs. Requires the hub state bucket
# policy to allow this account's role to s3:GetObject the hub key.
data "terraform_remote_state" "hub" {
  backend = "s3"

  config = {
    bucket = "acme-tfstate-network"
    key    = "network-hub/terraform.tfstate"
    region = "us-east-1"
  }
}

module "tgw_attachment" {
  source = "git::https://github.com/acme/terraform-aws-network.git//modules/tgw-spoke?ref=v0.1.0"

  attachment_name    = "workload-prod"
  transit_gateway_id = data.terraform_remote_state.hub.outputs.transit_gateway_id
  resource_share_arn = data.terraform_remote_state.hub.outputs.resource_share_arn

  # Invitation flow. Flip to false after enabling org-level RAM sharing.
  accept_ram_share = true

  vpc_id     = var.vpc_id
  subnet_ids = var.tgw_subnet_ids

  # Hub automation can key off these to pick the right route table.
  tags = {
    Segment     = "workloads"
    Environment = "prod"
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "spoke_account_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "tgw_subnet_ids" {
  description = "Dedicated /28 subnets, one per AZ."
  type        = list(string)
}

# The hub needs this to run tgw-routing.
output "attachment_id" {
  value = module.tgw_attachment.attachment_id
}
