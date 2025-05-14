using 'main.bicep'

param name = 'keyvault-il5-compliant'
param location = 'usgovvirginia'
param skuName = 'premium'
param enableRbacAuthorization = true
param enablePurgeProtection = true
param enableSoftDelete = true
param softDeleteRetentionInDays = 90
param publicNetworkAccess = 'Disabled'
param networkAcls = {
  bypass: 'AzureServices'
  defaultAction: 'Deny'
  ipRules: []
  virtualNetworkRules: []
}
param privateEndpoints = [
  {
    name: 'keyvault-il5-pe'
    subnetResourceId: '/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Network/virtualNetworks/{vnet-name}/subnets/{subnet-name}'
    privateDnsZoneGroups: [
      {
        privateDNSResourceIds: [
          '/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.usgovcloudapi.net'
        ]
      }
    ]
  }
]
param tags = {
  Environment: 'Production'
  Classification: 'CUI'
  ComplianceStandard: 'FedRAMP-High-DOD-IL5'
}
