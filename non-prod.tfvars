# environments/nonprod.tfvars
tenant_id           = "00000000-0000-0000-0000-000000000000"
subscription_ids    = {
  nonprod = "00000000-0000-0000-0000-000000000000"
  prod    = "11111111-1111-1111-1111-111111111111"
}
resource_group_name = "github-backup"
location            = "usgovvirginia"
vnet_name           = "nonprod-vnet"
vnet_resource_group_name = "network-rg"
subnet_name         = "backend-subnet"
vm_name             = "github-backup"
vm_size             = "Standard_D2s_v5"
admin_username      = "vmadmin"
key_vault_name      = "github-backup-kv"
key_vault_sku       = "premium"
admin_object_ids    = ["00000000-0000-0000-0000-000000000000"] # Replace with actual object IDs
enable_disk_encryption = true
enable_cmk         = true

# Bastion configuration if needed
use_bastion       = false
# bastion_host      = "bastion.example.com"
# bastion_user      = "bastionuser"

tags = {
  Environment = "nonprod"
  Application = "GitHub Backup"
  ComplianceLevel = "IL5"
  Owner       = "DevOps Team"
}
