1. Storage Account Compliance by Policy Assignment
kustoPolicyResources
| where type =~ 'Microsoft.PolicyInsights/PolicyStates'
| where properties.resourceType == 'Microsoft.Storage/storageAccounts'
| extend complianceState = tostring(properties.complianceState)
| extend
  resourceId = tostring(properties.resourceId),
  policyAssignmentName = tostring(properties.policyAssignmentName),
  policyDefinitionId = tostring(properties.policyDefinitionId)
| join kind=leftouter (
  Resources
  | where type =~ 'Microsoft.Storage/storageAccounts'
  | project resourceId=id, resourceName=name, resourceGroup, location, tags
) on resourceId
| summarize 
  TotalStorageAccounts = dcount(resourceId),
  CompliantCount = countif(complianceState == 'Compliant'),
  NonCompliantCount = countif(complianceState == 'NonCompliant'),
  ExemptCount = countif(complianceState == 'Exempt')
  by policyAssignmentName, resourceLocation=tostring(location)
| extend CompliancePercentage = round(todouble(CompliantCount) / todouble(TotalStorageAccounts) * 100, 2)
| order by CompliancePercentage asc
2. Non-Compliant Storage Accounts with Details
kustoPolicyResources
| where type == 'microsoft.policyinsights/policystates'
| where properties.complianceState == 'NonCompliant'
| where properties.resourceType == 'Microsoft.Storage/storageAccounts'
| extend 
  NonCompliantResourceId = properties.resourceId,
  PolicyAssignmentName = properties.policyAssignmentName,
  PolicyDefinitionId = properties.policyDefinitionId
| join kind=leftouter (
  Resources
  | where type =~ 'Microsoft.Storage/storageAccounts'
  | project id, name, resourceGroup, location, 
    publicNetworkAccess = properties.publicNetworkAccess,
    allowBlobPublicAccess = properties.allowBlobPublicAccess
) on $left.NonCompliantResourceId == $right.id
| project 
  StorageAccountName = name,
  ResourceGroup = resourceGroup,
  Location = location,
  PolicyAssignment = PolicyAssignmentName,
  PublicNetworkAccess = publicNetworkAccess,
  AllowBlobPublicAccess = allowBlobPublicAccess
3. Storage Account Compliance Summary with Exemptions
kustoPolicyResources
| where type == 'microsoft.policyinsights/policystates'
| where properties.resourceType == 'Microsoft.Storage/storageAccounts'
| extend complianceState = tostring(properties.complianceState)
| summarize 
  TotalResources = count(),
  CompliantCount = countif(complianceState == 'Compliant'),
  NonCompliantCount = countif(complianceState == 'NonCompliant'),
  ExemptCount = countif(complianceState == 'Exempt'),
  ConflictCount = countif(complianceState == 'Conflict')
| extend CompliancePercentage = round(todouble(CompliantCount + ExemptCount) / todouble(TotalResources) * 100, 2)
4. Policy Exemptions for Storage Accounts
kustoPolicyResources
| where type == 'microsoft.authorization/policyexemptions'
| extend expiresOn = todatetime(properties.expiresOn)
| where properties.metadata.resourceType == 'microsoft.storage/storageaccounts' or properties.policyAssignmentId contains 'storage'
| project 
  ExemptionName = name,
  DisplayName = properties.displayName,
  ExpiresOn = expiresOn,
  ExpiresInDays = datetime_diff('day', expiresOn, now()),
  PolicyAssignment = properties.policyAssignmentId
| where isnotnull(ExpiresOn) and ExpiresInDays <= 90
| order by ExpiresInDays asc
5. Storage Account Compliance by Subscription
kustoPolicyResources
| where type =~ 'Microsoft.PolicyInsights/PolicyStates'
| where properties.resourceType == 'Microsoft.Storage/storageAccounts'
| extend 
  complianceState = tostring(properties.complianceState),
  subscriptionId = tostring(properties.subscriptionId)
| summarize 
  TotalStorageAccounts = dcount(properties.resourceId),
  CompliantCount = countif(complianceState == 'Compliant'),
  NonCompliantCount = countif(complianceState == 'NonCompliant')
  by subscriptionId
| extend CompliancePercentage = round(todouble(CompliantCount) / todouble(TotalStorageAccounts) * 100, 2)
| join kind=leftouter (ResourceContainers | where type == 'microsoft.resources/subscriptions' | project subscriptionId, subscriptionName=name) on subscriptionId
| project SubscriptionName = subscriptionName, SubscriptionId = subscriptionId, TotalStorageAccounts, CompliantCount, NonCompliantCount, CompliancePercentage
| order by CompliancePercentage asc
