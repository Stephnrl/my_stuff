// Example of deploying a DoD IL5 compliant Key Vault in Azure Government with private endpoint
targetScope = 'resourceGroup'

// Parameters
@description('Name of the key vault')
param keyVaultName string = 'kv-il5-${uniqueString(resourceGroup().id)}'

@description('Location for all resources (should be Azure Government region)')
param location string = 'usgovvirginia'

@description('Object ID of the service principal who needs access to the Key Vault')
param servicePrincipalObjectId string

@description('Resource ID of the subnet for the private endpoint')
param subnetId string 

@description('Resource ID of the private DNS zone')
param privateDnsZoneId string

// Resources
module compliantKeyVault '../../main.bicep' = {
  name: 'il5KeyVault'
  params: {
    name: keyVaultName
    location: location
    complianceStandard: 'DoD-IL5'
    environment: 'Production'
    dataClassification: 'CUI'
    skuName: 'premium'
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    privateEndpoints: [
      {
        name: '${keyVaultName}-pe'
        subnetResourceId: subnetId
        privateDnsZoneGroups: [
          {
            privateDnsZoneConfigs: [
              {
                name: 'keyvault-dns-link'
                privateDnsZoneId: privateDnsZoneId
              }
            ]
          }
        ]
      }
    ]
    accessPolicies: [
      {
        objectId: servicePrincipalObjectId
        permissions: {
          keys: [
            'get'
            'list'
            'create'
            'update'
            'import'
            'delete'
            'recover'
            'backup'
            'restore'
          ]
          secrets: [
            'get'
            'list'
            'set'
            'delete'
            'recover'
            'backup'
            'restore'
          ]
          certificates: [
            'get'
            'list'
            'create'
            'update'
            'import'
            'delete'
            'recover'
            'backup'
            'restore'
            'managecontacts'
            'manageissuers'
            'getissuers'
            'listissuers'
            'setissuers'
            'deleteissuers'
          ]
        }
      }
    ]
    keys: [
      {
        name: 'encryption-key'
        keySize: 4096
        kty: 'RSA-HSM'
        rotationPolicy: {
          lifetimeActions: [
            {
              action: {
                type: 'Rotate'
              }
              trigger: {
                timeAfterCreate: 'P90D'
              }
            }
            {
              action: {
                type: 'Notify'
              }
              trigger: {
                timeBeforeExpiry: 'P30D'
              }
            }
          ]
        }
      }
    ]
    additionalTags: {
      Project: 'DoD Compliance'
      Owner: 'Security Team'
      Contract: 'GS-00F-000000'
    }
  }
}

output keyVaultName string = compliantKeyVault.outputs.keyVaultName
output keyVaultUri string = compliantKeyVault.outputs.keyVaultUri
output appliedComplianceStandard string = compliantKeyVault.outputs.appliedComplianceStandard
