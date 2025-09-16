# main.tf - Terraform module for Azure VM deployment using ARM templates

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

locals {
  # Generate unique deployment name
  deployment_name = "${var.vm_name}-deployment-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  
  # Construct the ARM template parameters
  arm_parameters = {
    vmName = {
      value = var.vm_name
    }
    location = {
      value = var.location
    }
    vmSize = {
      value = var.vm_size
    }
    adminUsername = {
      value = var.admin_username
    }
    adminPassword = {
      value = var.admin_password
    }
    sshKey = {
      value = var.ssh_public_key
    }
    subnetId = {
      value = var.subnet_id
    }
    imageId = {
      value = var.compute_gallery_image_id
    }
    osDiskName = {
      value = "${var.vm_name}-osdisk"
    }
    osDiskSizeGB = {
      value = var.os_disk_size_gb
    }
    osDiskType = {
      value = var.os_disk_type
    }
    dataDisks = {
      value = var.data_disks
    }
    enableAcceleratedNetworking = {
      value = var.enable_accelerated_networking
    }
    tags = {
      value = var.tags
    }
    usePublicIP = {
      value = var.use_public_ip
    }
    availabilityZone = {
      value = var.availability_zone
    }
  }
}

# Deploy the VM using ARM template
resource "azurerm_resource_group_template_deployment" "vm" {
  name                = local.deployment_name
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"
  
  parameters_content = jsonencode(local.arm_parameters)
  
  template_content = file("${path.module}/arm_template.json")
  
  tags = var.tags
  
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Parse outputs from ARM deployment
locals {
  deployment_outputs = try(jsondecode(azurerm_resource_group_template_deployment.vm.output_content), {})
}
