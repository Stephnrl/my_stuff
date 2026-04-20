// Control plane identity - for Private DNS, VNet, etc.
resource controlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: controlPlaneUMIName
  scope: resourceGroup(identityResourceGroup)
}

// Kubelet identity - for nodes, CSI drivers, ACR pulls
resource kubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: kubeletUMIName
  scope: resourceGroup(identityResourceGroup)
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: clusterName
  location: location

  // Control plane identity goes HERE
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${controlPlaneIdentity.id}': {}
    }
  }

  properties: {
    // Kubelet identity goes HERE (separate slot)
    identityProfile: {
      kubeletidentity: {
        resourceId: kubeletIdentity.id
        clientId: kubeletIdentity.properties.clientId
        objectId: kubeletIdentity.properties.principalId
      }
    }

    // rest of your cluster config...
    networkProfile: {
      networkPlugin: 'azure'
      privateDNSZone: privateDnsZoneId
    }
  }
}
