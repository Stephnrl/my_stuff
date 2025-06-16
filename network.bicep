// Parameters
@description('Name of the existing Virtual Network')
param vnetName string

@description('Resource Group where the existing VNet is located')
param vnetResourceGroupName string = resourceGroup().name

@description('Name of the new subnet')
param subnetName string

@description('Address prefix for the new subnet (e.g., 10.1.2.0/24)')
param subnetAddressPrefix string

@description('Location for resources')
param location string = resourceGroup().location

@description('Environment tag (e.g., dev, test, prod)')
param environment string = 'dev'

@description('Name prefix for resources')
param namePrefix string

@description('Tags to apply to resources')
param tags object = {
  Environment: environment
  ManagedBy: 'Bicep'
  Purpose: 'PrivateSubnet'
}

// Variables
var natGatewayName = '${namePrefix}-nat-gw-${environment}'
var natPublicIpName = '${namePrefix}-nat-pip-${environment}'
var nsgName = '${namePrefix}-nsg-${subnetName}-${environment}'

// Reference existing VNet
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroupName)
}

// Create Public IP for NAT Gateway
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: natPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

// Create NAT Gateway
resource natGateway 'Microsoft.Network/natGateways@2023-05-01' = {
  name: natGatewayName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
    idleTimeoutInMinutes: 4
  }
}

// Create Network Security Group
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowInboundFromVNet'
        properties: {
          description: 'Allow inbound traffic from VNet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowInboundFromAzureLoadBalancer'
        properties: {
          description: 'Allow inbound traffic from Azure Load Balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
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
        name: 'AllowOutboundToVNet'
        properties: {
          description: 'Allow outbound traffic to VNet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundToInternet'
        properties: {
          description: 'Allow outbound traffic to Internet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 110
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
  }
}

// Create the subnet with NAT Gateway and NSG association
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: existingVnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    natGateway: {
      id: natGateway.id
    }
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Outputs
@description('Resource ID of the created subnet')
output subnetId string = subnet.id

@description('Name of the created subnet')
output subnetName string = subnet.name

@description('Address prefix of the created subnet')
output subnetAddressPrefix string = subnet.properties.addressPrefix

@description('Resource ID of the NAT Gateway')
output natGatewayId string = natGateway.id

@description('Resource ID of the Network Security Group')
output networkSecurityGroupId string = networkSecurityGroup.id

@description('Public IP address of the NAT Gateway')
output natGatewayPublicIp string = natPublicIp.properties.ipAddress
