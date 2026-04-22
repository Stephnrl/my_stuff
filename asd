output "id" {
  description = "VM resource ID."
  value       = azurerm_linux_virtual_machine.this.id
}

output "name" {
  description = "VM name — also the Ansible inventory hostname."
  value       = azurerm_linux_virtual_machine.this.name
}

output "private_ip_address" {
  description = "Private IP. This is what AAP targets for SSH."
  value       = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "System-assigned managed identity principal ID (grant Key Vault / Log Analytics RBAC to this)."
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

output "admin_username" {
  description = "Local account AAP will SSH as."
  value       = var.admin_username
}

output "nic_id" {
  description = "NIC resource ID (useful for DCR / NSG association outside the module)."
  value       = azurerm_network_interface.this.id
}



variable "name" {
  description = "VM name. Also used as the prefix for the NIC and any module-owned child resources."
  type        = string
  validation {
    condition     = length(var.name) <= 64
    error_message = "Linux VM computer_name must be <= 64 chars."
  }
}

variable "resource_group_name" {
  description = "Resource group the VM lands in."
  type        = string
}

variable "location" {
  description = "Azure region (e.g. usgovvirginia, usgovtexas)."
  type        = string
}

variable "vm_size" {
  description = "VM SKU. Must be a Gen2 / Trusted Launch capable size when enable_trusted_launch = true."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "admin_username" {
  description = "Local service account used by AAP for SSH. Human users authenticate via Entra ID and should NOT use this account."
  type        = string
  default     = "aapadmin"
}

variable "admin_ssh_public_key" {
  description = "Public key for admin_username. The matching private key lives in an AAP Machine Credential — never in Git, never in tfvars."
  type        = string
  sensitive   = true
}

variable "subnet_id" {
  description = "Subnet resource ID. The NIC is deployed private-IP only — no public IP is ever created by this module."
  type        = string
}

variable "source_image_id" {
  description = "Compute Gallery image version ID produced by the Packer pipeline. Use the explicit version ID (not 'latest') so Terraform state matches what was actually deployed."
  type        = string
}

variable "data_disks" {
  description = "Managed data disks to create and attach."
  type = list(object({
    name                 = string
    lun                  = number
    disk_size_gb         = number
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadWrite")
  }))
  default = []
}

variable "os_disk_size_gb" {
  description = "OS disk size override. Leave null to inherit from the gallery image."
  type        = number
  default     = null
}

variable "disk_encryption_set_id" {
  description = "Disk Encryption Set ID backed by a customer-managed key in Key Vault. REQUIRED for CMMC L2 (NIST 800-171 3.13.11 / 3.13.16) when the VM processes CUI. Applied to OS + data disks."
  type        = string
}

variable "enable_trusted_launch" {
  description = "Enable Secure Boot + vTPM. Defaults on. Image in the gallery must be Gen2 / TrustedLaunchSupported."
  type        = bool
  default     = true
}

variable "enable_aad_ssh_login" {
  description = "Install the Entra ID SSH login extension for human access via 'az ssh vm'."
  type        = bool
  default     = true
}

variable "enable_azure_monitor_agent" {
  description = "Install Azure Monitor Agent. Pair with a Data Collection Rule association (outside this module) to ship syslog/auditd to Log Analytics / Sentinel."
  type        = bool
  default     = true
}

variable "user_assigned_identity_ids" {
  description = "User-assigned managed identity IDs (e.g. one with Key Vault access for AMA or secret retrieval). System-assigned identity is always enabled."
  type        = list(string)
  default     = []
}

variable "boot_diagnostics_storage_uri" {
  description = "Storage account blob URI for boot diagnostics. Set to null to use Azure-managed storage (simpler, and fine for CMMC)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags. Include at minimum: data_classification, cmmc_level, owner, cost_center."
  type        = map(string)
  default     = {}
  validation {
    condition     = contains(keys(var.tags), "data_classification") && contains(keys(var.tags), "cmmc_level")
    error_message = "tags must include 'data_classification' and 'cmmc_level' for audit/inventory traceability."
  }
}
