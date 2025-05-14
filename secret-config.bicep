@description('Required. The name of the Key Vault that contains the secret.')
param keyVaultName string

@description('Required. The name of the secret.')
param secretName string

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

@description('Optional. Whether to apply an expiration policy if none was provided.')
param applyExpirationPolicy bool = true

// Skip applying expiration if not needed
if (applyExpirationPolicy == false) {
  output message string = 'Expiration policy not applied as it was already set'
  output secretName string = secretName
  output complianceStandard string = complianceStandard
}

// Get existing Key Vault and secret references
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource existingSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' existing = {
  parent: keyVault
  name: secretName
}

// Get the existing secret value
resource getSecretValue 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (applyExpirationPolicy) {
  name: '${keyVaultName}-${secretName}-GetValue'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '7.0'
    retentionInterval: 'PT1H'
    arguments: '-KeyVaultName ${keyVaultName} -SecretName ${secretName}'
    scriptContent: '''
      param(
        [Parameter(Mandatory=$true)]
        [string] $KeyVaultName,
        
        [Parameter(Mandatory=$true)]
        [string] $SecretName
      )
      
      # Get the current secret value
      $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
      $secretValueText = '';
      
      if ($secret) {
        $secretValue = $secret.SecretValue
        $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretValue))
      }
      
      # Output the value as a DeploymentScript output
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['secretValue'] = $secretValueText
    '''
  }
}

// Apply the new secret with expiration based on compliance standards
resource updatedSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (applyExpirationPolicy) {
  parent: keyVault
  name: secretName
  properties: {
    // Retrieve the value from the previous deployment script
    value: applyExpirationPolicy ? getSecretValue.properties.outputs.secretValue : existingSecret.properties.value
    contentType: existingSecret.properties.contentType
    attributes: {
      enabled: existingSecret.properties.attributes.enabled
      // Set expiration time based on compliance standard
      exp: applyExpirationPolicy ? dateTimeToEpoch(dateTimeAdd(utcNow(), complianceStandard == 'FedRAMP-High' ? 'P365D' : (
              complianceStandard == 'DoD-IL5' ? 'P90D' : (
              complianceStandard == 'DoD-IL4' ? 'P180D' : 'P365D')))) : existingSecret.properties.attributes.exp
      nbf: existingSecret.properties.attributes.nbf
    }
  }
}

// Helper function to convert datetime to epoch seconds
func dateTimeToEpoch(dateTime string) int {
  // Convert to epoch seconds
  return dateTimeToTimestamp(dateTime) / 1000
}

@description('The resource ID of the updated secret.')
output secretId string = applyExpirationPolicy ? updatedSecret.id : existingSecret.id

@description('The compliance standard applied.')
output appliedComplianceStandard string = complianceStandard
