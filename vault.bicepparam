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

var complianceTags = {
  'FedRAMP-High': {
    'Compliance:Standard': 'FedRAMP'
    'Compliance:Level': 'High'
  }
  'FedRAMP-Moderate': {
    'Compliance:Standard': 'FedRAMP'
    'Compliance:Level': 'Moderate'
  }
  'DoD-IL4': {
    'Compliance:Standard': 'DoD'
    'Compliance:Level': 'IL4'
  }
  'DoD-IL5': {
    'Compliance:Standard': 'DoD'
    'Compliance:Level': 'IL5'
  }
  'DoD-IL6': {
    'Compliance:Standard': 'DoD'
    'Compliance:Level': 'IL6'
  }
  'HIPAA': {
    'Compliance:Standard': 'HIPAA'
  }
  'PCI-DSS': {
    'Compliance:Standard': 'PCI-DSS'
  }
  'None': {}
}

var baseTags = {
  Environment: environment
  'Data:Classification': dataClassification
}

output tags object = union(baseTags, complianceTags[complianceStandard], additionalTags)
