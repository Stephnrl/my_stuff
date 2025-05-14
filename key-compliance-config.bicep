@description('Required. The name of the Key Vault that contains the key.')
param keyVaultName string

@description('Required. The name of the key.')
param keyName string

@description('Required. The compliance standard to apply')
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
param complianceStandard string

@description('Optional. Whether to apply a rotation policy if none was provided.')
param applyRotationPolicy bool = true

// Get existing Key Vault and key references
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource key 'Microsoft.KeyVault/vaults/keys@2023-02-01' existing = {
  parent: keyVault
  name: keyName
}

// Apply compliance-specific rotation policies if needed
resource keyRotationPolicy 'Microsoft.KeyVault/vaults/keys/rotationpolicy@2023-02-01' = if (applyRotationPolicy) {
  parent: key
  name: 'default'
  properties: {
    lifetimeActions: [
      {
        trigger: {
          timeAfterCreate: complianceStandard == 'FedRAMP-High' ? 'P365D' : (
                          complianceStandard == 'DoD-IL5' ? 'P90D' : (
                          complianceStandard == 'DoD-IL4' ? 'P180D' : 'P365D'))
        }
        action: {
          type: 'Rotate'
        }
      }
      {
        trigger: {
          timeBeforeExpiry: 'P30D'
        }
        action: {
          type: 'Notify'
        }
      }
    ]
    attributes: {
      expiryTime: complianceStandard == 'FedRAMP-High' ? 'P13M' : (
                 complianceStandard == 'DoD-IL5' ? 'P4M' : (
                 complianceStandard == 'DoD-IL4' ? 'P7M' : 'P13M'))
    }
  }
}

@description('The rotation policy ID.')
output rotationPolicyId string = applyRotationPolicy ? keyRotationPolicy.id : ''

@description('The compliance standard applied.')
output appliedComplianceStandard string = complianceStandard
