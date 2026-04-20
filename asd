// Control plane UMI needs 'Managed Identity Operator' over the kubelet UMI
resource managedIdentityOperatorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kubeletIdentity.id, controlPlaneIdentity.id, 'Managed Identity Operator')
  scope: kubeletIdentity
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'f1a07417-d97a-45cb-824c-7a7467783830'  // Managed Identity Operator
    )
    principalId: controlPlaneIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
