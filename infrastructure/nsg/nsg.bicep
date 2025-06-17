// infrastructure/nsg/nsg.bicep
@description('Name of the Network Security Group')
param nsgName string

@description('Location for the NSG')
param location string = resourceGroup().location

@description('Tags to apply to the NSG')
param tags object = {}

@description('Environment to determine which rule set to use')
param environment string = 'dev'

@description('Rule set name to load from JSON file')
param ruleSetName string = 'default'

// Load rules from JSON file using loadJsonContent
var allRuleSets = loadJsonContent('nsg-rules.json')

// Get the specific rule set for the environment and rule set name
var environmentRules = allRuleSets[environment]
var selectedRules = environmentRules[ruleSetName]

// Base rules that are always applied
var baseRules = [
  {
    name: 'AllowVnetInbound'
    properties: {
      description: 'Allow inbound traffic from VNet'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 4000
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowAzureLoadBalancerInbound'
    properties: {
      description: 'Allow inbound traffic from Azure Load Balancer'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: 'AzureLoadBalancer'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 4001
      direction: 'Inbound'
    }
  }
  {
    name: 'DenyAllInbound'
    properties: {
      description: 'Deny all other inbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      priority: 4096
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowVnetOutbound'
    properties: {
      description: 'Allow outbound traffic to VNet'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      priority: 4000
      direction: 'Outbound'
    }
  }
  {
    name: 'AllowInternetOutbound'
    properties: {
      description: 'Allow outbound traffic to Internet'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: 'Internet'
      access: 'Allow'
      priority: 4001
      direction: 'Outbound'
    }
  }
  {
    name: 'DenyAllOutbound'
    properties: {
      description: 'Deny all other outbound traffic'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      priority: 4096
      direction: 'Outbound'
    }
  }
]

// Combine JSON rules with base rules
var combinedRules = concat(selectedRules, baseRules)

// Create Network Security Group
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [for rule in combinedRules: {
      name: rule.name
      properties: rule.properties
    }]
  }
}

// Outputs
output nsgId string = networkSecurityGroup.id
output nsgName string = networkSecurityGroup.name
output rulesCount int = length(combinedRules)
