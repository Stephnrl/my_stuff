terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
    # azurerm cannot create a custom Log Analytics table with a schema
    # (azurerm_log_analytics_table only manages retention on existing tables),
    # so the DCR-based custom table goes through the ARM API directly.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.2"
    }
  }

  backend "azurerm" {
    # Values supplied via -backend-config. use_azuread_auth keeps state access
    # on the same OIDC federated credential as everything else - no storage keys.
    use_azuread_auth = true
    use_oidc         = true
  }
}

provider "azurerm" {
  features {}
  environment = "usgovernment"
  use_oidc    = true
}

provider "azapi" {
  environment = "usgovernment"
  use_oidc    = true
}

data "azurerm_client_config" "current" {}

locals {
  name_prefix = "${var.name_prefix}-${var.environment_suffix}"

  tags = merge(var.tags, {
    managed_by  = "terraform"
    system      = "container-security-gate"
    data_class  = "CUI"
  })
}

resource "azurerm_resource_group" "gate" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}
