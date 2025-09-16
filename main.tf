# outputs.tf - Output values from the Azure VM ARM template deployment

output "vm_id" {
  description = "Resource ID of the deployed virtual machine"
  value       = try(local.deployment_outputs.vmId.value, "")
}

output "private_ip_address" {
  description = "Private IP address of the VM"
  value       = try(local.deployment_outputs.privateIpAddress.value, "")
}

output "public_ip_address" {
  description = "Public IP address of the VM (if public IP was created)"
  value       = try(local.deployment_outputs.publicIpAddress.value, "")
}

output "nic_id" {
  description = "Resource ID of the network interface"
  value       = try(local.deployment_outputs.nicId.value, "")
}

output "os_disk_id" {
  description = "Resource ID of the OS disk"
  value       = try(local.deployment_outputs.osDiskId.value, "")
}

output "deployment_id" {
  description = "ID of the ARM template deployment"
  value       = azurerm_resource_group_template_deployment.vm.id
}

output "deployment_output_content" {
  description = "Raw output content from the ARM deployment (for debugging)"
  value       = azurerm_resource_group_template_deployment.vm.output_content
  sensitive   = true
}
