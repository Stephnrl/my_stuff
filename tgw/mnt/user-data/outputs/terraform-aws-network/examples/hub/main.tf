###############################################################################
# Root module for the netops hub account.
# Lives in its own repo (e.g. tf-network-hub), NOT in the module repo.
###############################################################################

terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket       = "acme-tfstate-network"
    key          = "network-hub/terraform.tfstate"
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

# GitHub OIDC assumes a bootstrap role, which chains into the network account.
# Role chaining caps session length at 1 hour regardless of max_session_duration.
provider "aws" {
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${var.network_account_id}:role/TerraformExecution"
    session_name = "gha-network-hub"
  }

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "acme/tf-network-hub"
    }
  }
}

module "tgw_hub" {
  source = "git::https://github.com/acme/terraform-aws-network.git//modules/tgw-hub?ref=v0.1.0"

  name        = "acme-hub-tgw"
  share_name  = "acme-tgw-spoke-share"
  description = "Landing zone hub transit gateway"

  # Invitation flow: enumerate spoke accounts explicitly.
  # After enabling org sharing, replace with a single OU ARN:
  #   ["arn:aws:organizations::${var.mgmt_account_id}:ou/${var.org_id}/${var.workloads_ou_id}"]
  shared_principals = var.spoke_account_ids

  # Hub reviews each attachment before it lands.
  auto_accept_shared_attachments = false

  # Segmented topology. For a flat start, drop route_tables and leave both
  # default_* flags at their true defaults.
  default_route_table_association = false
  default_route_table_propagation = false

  route_tables = {
    workloads       = {}
    shared-services = {}
  }

  tags = { Environment = "shared" }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "network_account_id" {
  type = string
}

variable "spoke_account_ids" {
  type    = set(string)
  default = []
}

output "transit_gateway_id" {
  value = module.tgw_hub.transit_gateway_id
}

output "resource_share_arn" {
  value = module.tgw_hub.resource_share_arn
}
