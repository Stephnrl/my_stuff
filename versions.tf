variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "subscription_ids" {
  description = "Map of subscription IDs for each environment"
  type        = map(string)
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "usgovvirginia"
}

# Existing network resources
variable "vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Resource group name of the existing virtual network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the existing subnet"
  type        = string
}

# VM configuration
variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "admin_username" {
  description = "Username for the VM admin account"
  type        = string
  default     = "vmadmin"
}

variable "ssh_public_key" {
  description = "SSH public key for the VM admin account"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for remote-exec connections"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# Bastion host variables
variable "use_bastion" {
  description = "Whether to use a bastion host for SSH connections"
  type        = bool
  default     = false
}

variable "bastion_host" {
  description = "Hostname or IP of the bastion host"
  type        = string
  default     = ""
}

variable "bastion_user" {
  description = "Username for the bastion host"
  type        = string
  default     = ""
}

variable "bastion_private_key_path" {
  description = "Path to SSH private key for bastion host connections"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# Key Vault configuration
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
}

variable "key_vault_sku" {
  description = "SKU of the Key Vault"
  type        = string
  default     = "premium" # Premium SKU for FIPS compliance
}

# Access control
variable "admin_object_ids" {
  description = "List of Azure AD Object IDs that require Key Vault admin access"
  type        = list(string)
  default     = []
}

# IL5 compliance settings
variable "enable_disk_encryption" {
  description = "Enable disk encryption for IL5 compliance"
  type        = bool
  default     = true
}

variable "enable_cmk" {
  description = "Enable customer-managed keys for IL5 compliance"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Ansible Path
variable "ansible_path" {
  description = "Path to ansible directory to copy to VM"
  type        = string
  default     = "./ansible"
}

# GitHub Backup configuration
variable "github_pat_secret_name" {
  description = "Name of the Key Vault secret for GitHub PAT"
  type        = string
  default     = "github-pat"
}
