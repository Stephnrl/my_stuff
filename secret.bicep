@description('Required. The name of the secret.')
param name string

@description('Required. The value of the secret.')
@secure()
param value string

@description('Required. The name of the key vault.')
param keyVaultName string

@description('Optional. Resource tags.')
param tags object = {}

@description('Optional. Content type of the secret.')
param contentType string = ''

@description('Optional. Determines whether the object is enabled.')
param attributesEnabled bool = true

@description('Optional. Expiry date in seconds since 1970-01-01T00:00:00Z. Set to -1 to not expire.')
param attributesExp int = -1

@description('Optional. Not before date in seconds since 1970-01-01T00:00:00Z. Set to -1 to use now.')
param attributesNbf int = -1

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
module complianceTags '../../../../shared/compliance-tags.bicep' = {
  name: '${keyVaultName}-${name}-ComplianceTags'
  params: {
    complianceStandard: complianceStandard
    environment: environment
    dataClassification: dataClassification
    additionalTags: additionalTags
  }
}

// Get existing Key Vault reference
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Create the secret
resource secret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: name
  tags: union(tags, complianceTags.outputs.tags)
  properties: {
    value: value
    contentType: contentType
    attributes: {
      enabled: attributesEnabled
      exp: attributesExp != -1 ? attributesExp : null
      nbf: attributesNbf != -1 ? attributesNbf : null
    }
  }
}

// Apply specific expirations for compliance (secrets should have expirations for high compliance)
module secretComplianceConfig 'secret-compliance-config.bicep' = if (complianceStandard == 'FedRAMP-High' || complianceStandard == 'DoD-IL5' || complianceStandard == 'DoD-IL4') {
  name: '${keyVaultName}-${name}-ComplianceConfig'
  params: {
    keyVaultName: keyVaultName
    secretName: name
    complianceStandard: complianceStandard
    // Only apply if no expiration was provided
    applyExpirationPolicy: attributesExp == -1
  }
}

// Output secret details
@description('The name of the secret.')
output name string = secret.name

@description('The resource ID of the secret.')
output resourceId string = secret.id

@description('The name of the resource group the secret was created in.')
output resourceGroupName string = resourceGroup().name

@description('The compliance standard applied.')
output appliedComplianceStandard string = complianceStandard
