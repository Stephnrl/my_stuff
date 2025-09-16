# variables.tf - Input variables for the Azure VM ARM template module

variable "resource_group_name" {
  description = "Name of the resource group where the VM will be deployed"
  type        = string
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "location" {
  description = "Azure region for the VM deployment"
  type        = string
}

variable "vm_size" {
  description = "Size of the virtual machine (must support Gen2 and Trusted Launch)"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password (required if SSH key not provided)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for authentication (recommended over password)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Resource ID of the subnet for the VM's NIC"
  type        = string
}

variable "compute_gallery_image_id" {
  description = "Resource ID of the Compute Gallery Image Version (RHEL 9 Gen2 with Trusted Launch)"
  type        = string
  # Example format: /subscriptions/{subscription-id}/resourceGroups/{rg}/providers/Microsoft.Compute/galleries/{gallery}/images/{image}/versions/{version}
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 128
}

variable "os_disk_type" {
  description = "Storage type for the OS disk"
  type        = string
  default     = "Premium_LRS"
  validation {
    condition = contains([
      "Standard_LRS",
      "Premium_LRS",
      "StandardSSD_LRS",
      "Premium_ZRS",
      "StandardSSD_ZRS"
    ], var.os_disk_type)
    error_message = "Invalid OS disk type specified."
  }
}

variable "data_disks" {
  description = "List of data disk configurations"
  type = list(object({
    name                = string
    diskSizeGB          = number
    lun                 = number
    storageAccountType  = string
  }))
  default = []
  # Example:
  # [
  #   {
  #     name               = "data1"
  #     diskSizeGB        = 256
  #     lun               = 0
  #     storageAccountType = "Premium_LRS"
  #   },
  #   {
  #     name               = "data2"
  #     diskSizeGB        = 512
  #     lun               = 1
  #     storageAccountType = "StandardSSD_LRS"
  #   }
  # ]
}

variable "enable_accelerated_networking" {
  description = "Enable accelerated networking on the VM's NIC"
  type        = bool
  default     = true
}

variable "use_public_ip" {
  description = "Whether to create and attach a public IP address"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Availability zone for the VM (1, 2, 3, or empty for no zone)"
  type        = string
  default     = ""
  validation {
    condition = var.availability_zone == "" || contains(["1", "2", "3"], var.availability_zone)
    error_message = "Availability zone must be 1, 2, 3, or empty."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
