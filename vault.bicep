@description('Required. Name of the Key Vault.')
param name string

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. Specifies the Azure Active Directory tenant ID that should be used for authenticating requests to the key vault.')
param tenantId string = tenant().tenantId

@description('Optional. Array of access policies object.')
param accessPolicies array = []

@description('Optional. All secrets to create.')
param secrets array = []

@description('Optional. All keys to create.')
param keys array = []

@description('Optional. All certificates to create.')
param certificates array = []

@description('Optional. Resource tags.')
param tags object = {}

@description('Optional. Service endpoint object information.')
param networkAcls object = {}

@description('Optional. Property that controls how data actions are authorized. When true, the key vault will use Role Based Access Control (RBAC) for authorization of data actions, and the access policies specified in vault properties will be ignored.')
param enableRbacAuthorization bool = true

@description('Optional. Provide "true" to enable Key Vault\'s purge protection feature.')
param enablePurgeProtection bool = true

@description('Optional. Provide "true" to enable Key Vault\'s soft delete feature.')
param enableSoftDelete bool = true

@description('Optional. softDelete data retention days. It accepts >=7 and <=90.')
param softDeleteRetentionInDays int = 90

@description('Optional. Specifies if the vault is enabled for deployment by script or compute.')
param enabledForDeployment bool = false

@description('Optional. Specifies if the vault is enabled for a template deployment.')
param enabledForTemplateDeployment bool = false

@description('Optional. Specifies if the azure platform has access to the vault for enabling disk encryption scenarios.')
param enabledForDiskEncryption bool = false

@description('Optional. Specifies the SKU name of the key vault.')
@allowed([
  'premium'
  'standard'
])
param skuName string = 'premium'

@description('Optional. Specifies if the public network access is allowed')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Optional. The private endpoints to create for the key vault.')
param privateEndpoints array = []

// Create the Key Vault with compliance settings
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: name
  location: location
  tags: union(tags, {
    'FedRAMPCompliance': 'High'
    'DoDComplianceLevel': 'IL4-IL5'
  })
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    enabledForDeployment: enabledForDeployment
    enabledForTemplateDeployment: enabledForTemplateDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enableRbacAuthorization: enableRbacAuthorization
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: publicNetworkAccess
    networkAcls: !empty(networkAcls) ? {
      bypass: contains(networkAcls, 'bypass') ? networkAcls.bypass : 'AzureServices'
      defaultAction: contains(networkAcls, 'defaultAction') ? networkAcls.defaultAction : 'Deny'
      ipRules: contains(networkAcls, 'ipRules') ? networkAcls.ipRules : []
      virtualNetworkRules: contains(networkAcls, 'virtualNetworkRules') ? networkAcls.virtualNetworkRules : []
    } : null
    accessPolicies: [for accessPolicy in accessPolicies: {
      tenantId: contains(accessPolicy, 'tenantId') ? accessPolicy.tenantId : tenantId
      objectId: accessPolicy.objectId
      permissions: accessPolicy.permissions
      applicationId: contains(accessPolicy, 'applicationId') ? accessPolicy.applicationId : null
    }]
  }
}

// Create secrets if specified
module keyVaultSecrets 'br:bicep/modules/microsoft.keyvault.secret:1.0.0' = [for secret in secrets: if (!empty(secrets)) {
  name: '${name}-secret-${secret.name}'
  params: {
    name: secret.name
    value: secret.value
    keyVaultName: keyVault.name
    attributesEnabled: contains(secret, 'attributesEnabled') ? secret.attributesEnabled : true
    attributesExp: contains(secret, 'attributesExp') ? secret.attributesExp : -1
    attributesNbf: contains(secret, 'attributesNbf') ? secret.attributesNbf : -1
    contentType: contains(secret, 'contentType') ? secret.contentType : ''
    tags: contains(secret, 'tags') ? secret.tags : {}
  }
}]

// Create keys if specified
module keyVaultKeys 'br:bicep/modules/microsoft.keyvault.key:1.0.0' = [for key in keys: if (!empty(keys)) {
  name: '${name}-key-${key.name}'
  params: {
    name: key.name
    keyVaultName: keyVault.name
    attributesEnabled: contains(key, 'attributesEnabled') ? key.attributesEnabled : true
    attributesExp: contains(key, 'attributesExp') ? key.attributesExp : -1
    attributesNbf: contains(key, 'attributesNbf') ? key.attributesNbf : -1
    keySize: contains(key, 'keySize') ? key.keySize : 2048
    kty: contains(key, 'kty') ? key.kty : 'RSA'
    keyOps: contains(key, 'keyOps') ? key.keyOps : []
    tags: contains(key, 'tags') ? key.tags : {}
    rotationPolicy: contains(key, 'rotationPolicy') ? key.rotationPolicy : null
  }
}]

// Create certificates if specified
module keyVaultCertificates 'br:bicep/modules/microsoft.keyvault.certificate:1.0.0' = [for certificate in certificates: if (!empty(certificates)) {
  name: '${name}-certificate-${certificate.name}'
  params: {
    name: certificate.name
    keyVaultName: keyVault.name
    attributesEnabled: contains(certificate, 'attributesEnabled') ? certificate.attributesEnabled : true
    attributesExp: contains(certificate, 'attributesExp') ? certificate.attributesExp : -1
    attributesNbf: contains(certificate, 'attributesNbf') ? certificate.attributesNbf : -1
    certificateAttributes: contains(certificate, 'certificateAttributes') ? certificate.certificateAttributes : {}
    certificatePolicy: contains(certificate, 'certificatePolicy') ? certificate.certificatePolicy : {
      keyProperties: {
        exportable: true
        keySize: 2048
        keyType: 'RSA'
        reuseKey: false
      }
      secretProperties: {
        contentType: 'application/x-pkcs12'
      }
      issuerParameters: {
        name: 'Self'
      }
      lifetimeActions: [
        {
          action: {
            actionType: 'AutoRenew'
          }
          trigger: {
            daysBeforeExpiry: 90
          }
        }
      ]
      x509CertificateProperties: {
        keyUsage: [
          'digitalSignature'
          'keyEncipherment'
        ]
        subject: 'CN=${certificate.name}'
        validityInMonths: 12
      }
    }
    tags: contains(certificate, 'tags') ? certificate.tags : {}
  }
}]

// Create private endpoints if specified
module privateEndpoint 'br:bicep/modules/microsoft.network.privateendpoint:1.0.0' = [for (privateEndpoint, index) in privateEndpoints: if (!empty(privateEndpoints)) {
  name: '${name}-privateEndpoint-${index}'
  params: {
    name: contains(privateEndpoint, 'name') ? privateEndpoint.name : '${name}-PrivateEndpoint-${index}'
    location: location
    subnetResourceId: privateEndpoint.subnetResourceId
    privateLinkServiceConnections: [
      {
        name: contains(privateEndpoint, 'privateLinkServiceConnectionName') ? privateEndpoint.privateLinkServiceConnectionName : '${name}-PrivateLink-${index}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
    privateDnsZoneGroups: contains(privateEndpoint, 'privateDnsZoneGroups') ? privateEndpoint.privateDnsZoneGroups : []
    ipConfigurations: contains(privateEndpoint, 'ipConfigurations') ? privateEndpoint.ipConfigurations : []
    customNetworkInterfaceName: contains(privateEndpoint, 'customNetworkInterfaceName') ? privateEndpoint.customNetworkInterfaceName : null
    tags: contains(privateEndpoint, 'tags') ? privateEndpoint.tags : {}
  }
}]

// Output the Key Vault ID and URI
@description('The resource ID of the key vault.')
output keyVaultId string = keyVault.id

@description('The name of the key vault.')
output keyVaultName string = keyVault.name

@description('The URI of the key vault.')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The location the resource was deployed into.')
output location string = keyVault.location
