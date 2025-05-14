@description('Required. The name of the key.')
param name string

@description('Required. The name of the key vault.')
param keyVaultName string

@description('Optional. Resource tags.')
param tags object = {}

@description('Optional. Key type. Possible values include: "EC", "EC-HSM", "RSA", "RSA-HSM", "oct".')
@allowed([
  'EC'
  'EC-HSM'
  'RSA'
  'RSA-HSM'
  'oct'
])
param kty string = 'RSA'

@description('Optional. The key size in bits. For example: 2048, 3072, or 4096 for RSA.')
param keySize int = 2048

@description('Optional. Array of JsonWebKeyOperation.')
param keyOps array = []

@description('Optional. Indicates if the key is enabled.')
param attributesEnabled bool = true

@description('Optional. Expiry date in seconds since 1970-01-01T00:00:00Z. Set to -1 to not expire.')
param attributesExp int = -1

@description('Optional. Not before date in seconds since 1970-01-01T00:00:00Z. Set to -1 to use now.')
param attributesNbf int = -1

@description('Optional. The elliptic curve name. For valid values, see JsonWebKeyCurveName.')
@allowed([
  'P-256'
  'P-256K'
  'P-384'
  'P-521'
])
param curveName string = 'P-256'

@description('Optional. Creation policy for hsm-backed keys.')
param hsm bool = true

@description('Optional. Key rotation policy for the key.')
param rotationPolicy object = {}

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

// Create the key
resource key 'Microsoft.KeyVault/vaults/keys@2023-02-01' = {
  parent: keyVault
  name: name
  tags: union(tags, complianceTags.outputs.tags)
  properties: {
    kty: kty
    keySize: keySize
    keyOps: !empty(keyOps) ? keyOps : null
    attributes: {
      enabled: attributesEnabled
      exp: attributesExp != -1 ? attributesExp : null
      nbf: attributesNbf != -1 ? attributesNbf : null
    }
    curveName: kty == 'EC' || kty == 'EC-HSM' ? curveName : null
    rotationPolicy: !empty(rotationPolicy) ? rotationPolicy : null
  }
}

// Apply specific key settings for FedRAMP/DoD compliance
// For FedRAMP High and DoD IL5, enforce minimum key length and rotation policy if not specified
module complianceConfig 'key-compliance-config.bicep' = if (complianceStandard == 'FedRAMP-High' || complianceStandard == 'DoD-IL5' || complianceStandard == 'DoD-IL4') {
  name: '${keyVaultName}-${name}-ComplianceConfig'
  params: {
    keyVaultName: keyVaultName
    keyName: name
    complianceStandard: complianceStandard
    // Only apply if no rotation policy was provided
    applyRotationPolicy: empty(rotationPolicy)
  }
}

// Output key details
@description('The name of the key.')
output name string = key.name

@description('The resource ID of the key.')
output resourceId string = key.id

@description('The name of the resource group the key was created in.')
output resourceGroupName string = resourceGroup().name

@description('The compliance standard applied.')
output appliedComplianceStandard string = complianceStandard
