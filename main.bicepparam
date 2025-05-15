using './main.bicep'

param environmentName = 'prod'
param location = 'usgovvirginia'
param resourceGroupName = 'terraform-bootstrap-prod'
param vnetName = 'prod-vnet'
param subnetName = 'backend-subnet'
param vnetResourceGroupName = 'network-rg'
param tags = {
  Environment: 'prod'
  Purpose: 'Terraform State'
  ManagedBy: 'Bicep'
  ComplianceLevel: 'IL5'
}
