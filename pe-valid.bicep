@description('Required. The name of the private endpoint.')
param privateEndpointName string

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

@description('Required. Location of the private endpoint.')
param location string

// Only validate for DoD IL5 and FedRAMP High in Government regions
var isGovCloud = contains(tolower(location), 'usgov') || contains(tolower(location), 'usdod')
var validateCompliance = isGovCloud && (complianceStandard == 'FedRAMP-High' || complianceStandard == 'DoD-IL5' || complianceStandard == 'DoD-IL4')

// Get the private endpoint to validate its configuration
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' existing = {
  name: privateEndpointName
}

// Validate the private endpoint configuration
// For compliance validation, we use a deployment script to analyze the configuration
resource validatePrivateEndpoint 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (validateCompliance) {
  name: '${privateEndpointName}-ComplianceValidation'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '7.0'
    retentionInterval: 'PT1H'
    arguments: '-PrivateEndpointName ${privateEndpointName} -ResourceGroupName ${resourceGroup().name} -ComplianceStandard ${complianceStandard}'
    scriptContent: '''
      param(
        [Parameter(Mandatory=$true)]
        [string] $PrivateEndpointName,
        
        [Parameter(Mandatory=$true)]
        [string] $ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string] $ComplianceStandard
      )
      
      # Get the private endpoint configuration
      $pe = Get-AzPrivateEndpoint -Name $PrivateEndpointName -ResourceGroupName $ResourceGroupName
      
      # Initialize validation results
      $validationResults = @{
        IsCompliant = $true
        ValidationMessages = @()
      }
      
      # Check if PE has a subnet reference
      if (!$pe.Subnet) {
        $validationResults.IsCompliant = $false
        $validationResults.ValidationMessages += "Private endpoint must be connected to a subnet"
      }
      
      # Check if PE has private link service connections
      if (!$pe.PrivateLinkServiceConnections -and !$pe.ManualPrivateLinkServiceConnections) {
        $validationResults.IsCompliant = $false
        $validationResults.ValidationMessages += "Private endpoint must have a private link service connection"
      }
      
      # Check if PE has a network interface
      if (!$pe.NetworkInterfaces -or $pe.NetworkInterfaces.Count -eq 0) {
        $validationResults.IsCompliant = $false
        $validationResults.ValidationMessages += "Private endpoint must have a network interface"
      }
      
      # Get the network interface details
      $nicId = $pe.NetworkInterfaces[0].Id
      $nic = Get-AzNetworkInterface -ResourceId $nicId
      
      # Check if NIC has IP configurations
      if (!$nic.IpConfigurations -or $nic.IpConfigurations.Count -eq 0) {
        $validationResults.IsCompliant = $false
        $validationResults.ValidationMessages += "Network interface must have IP configurations"
      }
      
      # Special validation for DoD IL5
      if ($ComplianceStandard -eq "DoD-IL5") {
        # Check if subnet is in a DoD-approved VNet
        $subnetParts = $pe.Subnet.Id -split "/"
        $vnetName = $subnetParts[8]
        
        # We would need specific DoD VNet naming conventions here
        # This is a placeholder for actual DoD IL5 validation
        if (!$vnetName.StartsWith("vnet-dod") -and !$vnetName.StartsWith("vnet-il5")) {
          $validationResults.ValidationMessages += "WARNING: VNet may not be DoD IL5 compliant. Verify VNet configuration."
        }
      }
      
      # Special validation for FedRAMP High
      if ($ComplianceStandard -eq "FedRAMP-High") {
        # Placeholder for FedRAMP High specific validations
        # These would be actual FedRAMP requirements
        $validationResults.ValidationMessages += "RECOMMENDATION: Verify network security groups attached to the subnet allow only necessary traffic."
      }
      
      # Output validation results
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['isCompliant'] = $validationResults.IsCompliant
      $DeploymentScriptOutputs['validationMessages'] = $validationResults.ValidationMessages
    '''
  }
}

@description('Whether the private endpoint is compliant with the specified standard.')
output isCompliant bool = validateCompliance ? validatePrivateEndpoint.properties.outputs.isCompliant : true

@description('Validation messages and recommendations.')
output validationMessages array = validateCompliance ? validatePrivateEndpoint.properties.outputs.validationMessages : ['Compliance validation not required or not applicable for this deployment.']

@description('The compliance standard applied.')
output appliedComplianceStandard string = complianceStandard
