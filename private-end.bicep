@description('Required. The name of the private endpoint resource.')
param name string

@description('Required. Resource ID of the resource to connect to.')
param serviceResourceId string

@description('Required. Resource ID of the subnet where the private endpoint will be created.')
param subnetResourceId string

@description('Required. Subresource name of the resource to connect to.')
@allowed([
  'vault'              // Key Vault
  'table'              // Storage account - table
  'blob'               // Storage account - blob
  'file'               // Storage account - file
  'queue'              // Storage account - queue
  'web'                // App Service
  'sites'              // App Service
  'sqlServer'          // SQL Server
  'mysqlServer'        // MySQL
  'postgresqlServer'   // PostgreSQL
  'database'           // CosmosDB
  'registry'           // Container Registry
])
param groupId string = 'vault'

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. The private DNS zone group configuration used to associate the private endpoint with DNS zones.')
param privateDnsZoneGroups array = []

@description('Optional. Custom network interface name for the private endpoint.')
param customNetworkInterfaceName string = ''

@description('Optional. Application security groups in which the private endpoint IP configuration is included.')
param applicationSecurityGroups array = []

@description('Optional. A list of IP configurations of the private endpoint. This will be used to map to the First Party Service endpoints.')
param ipConfigurations array = []

@description('Optional. Custom DNS configurations.')
param customDnsConfigs array = []

@description('Optional. Resource tags.')
param tags object = {}

@description('Optional. The compliance standard to apply')
@allowed([
  'FedRAMP-High'
  'FedRAMP-Moderate'
  'DoD-IL4'
  'DoD-IL5'
  'DoD-IL6'
  'HIPAA'
  'PCI-DSS'
  'None'
])
param complianceStandard string = 'None'

@description('Optional. The environment this resource is deployed to')
@allowed([
  'Production'
  'Staging'
  'Test'
  'Development'
])
param environment string = 'Development'

@description('Optional. The data classification of the resource')
@allowed([
  'Public'
  'Internal'
  'Confidential' 
  'CUI'
  'Restricted'
])
param dataClassification string = 'Internal'

@description('Optional. Additional tags to apply')
param additionalTags object = {}

// Import shared compliance tags module
module complianceTags '../../../shared/compliance-tags.bicep' = {
  name: '${name}-ComplianceTags'
  params: {
    complianceStandard: complianceStandard
    environment: environment
    dataClassification: dataClassification
    additionalTags: additionalTags
  }
}

var privateDnsZoneGroupName = 'default'

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: name
  location: location
  tags: union(tags, complianceTags.outputs.tags)
  properties: {
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: serviceResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
    customNetworkInterfaceName: !empty(customNetworkInterfaceName) ? customNetworkInterfaceName : null
    applicationSecurityGroups: !empty(applicationSecurityGroups) ? applicationSecurityGroups : null
    ipConfigurations: !empty(ipConfigurations) ? ipConfigurations : null
    customDnsConfigs: !empty(customDnsConfigs) ? customDnsConfigs : null
    subnet: {
      id: subnetResourceId
    }
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = [for (privateDnsZoneGroup, index) in privateDnsZoneGroups: {
  parent: privateEndpoint
  name: privateDnsZoneGroupName
  properties: {
    privateDnsZoneConfigs: [for privateDnsZoneConfig in privateDnsZoneGroup.privateDnsZoneConfigs: {
      name: contains(privateDnsZoneConfig, 'name') ? privateDnsZoneConfig.name : 'default'
      properties: {
        privateDnsZoneId: privateDnsZoneConfig.privateDnsZoneId
      }
    }]
  }
}]

// Auto-detect if this is a DoD IL5 or FedRAMP High deployment to Azure Government
// If so, validate that the network configuration meets the compliance requirements
module privateEndpointComplianceValidator 'private-endpoint-compliance-validator.bicep' = if (complianceStandard == 'FedRAMP-High' || complianceStandard == 'DoD-IL5' || complianceStandard == 'DoD-IL4') {
  name: '${name}-ComplianceValidator'
  params: {
    privateEndpointName: privateEndpoint.name
    complianceStandard: complianceStandard
    location: location
  }
}

@description('The resource ID of the private endpoint.')
output privateEndpointId string = privateEndpoint.id

@description('The resource name of the private endpoint.')
output privateEndpointName string = privateEndpoint.name

@description('The resource group the private endpoint was deployed into.')
output privateEndpointResourceGroup string = resourceGroup().name

@description('The location the private endpoint was deployed into.')
output privateEndpointLocation string = privateEndpoint.location

@description('The NIC name of the private endpoint.')
output nicName string = privateEndpoint.properties.networkInterfaces[0].name

@description('The NIC resource ID of the private endpoint.')
output nicResourceId string = privateEndpoint.properties.networkInterfaces[0].id

@description('The compliance standard applied.')
output appliedComplianceStandard string = complianceStandard
