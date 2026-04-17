ApiManagementGatewayLogs
| where TimeGenerated > ago(30d)
| where BackendUrl contains "appserviceenvironment.us"
| summarize 
    SuccessCount = countif(IsRequestSuccess == true),
    FailureCount = countif(IsRequestSuccess == false)
    by bin(TimeGenerated, 1h)
| order by TimeGenerated desc
| render timechart

ApiManagementGatewayLogs
| where TimeGenerated > ago(30d)
| where BackendUrl contains "appserviceenvironment.us"
| summarize 
    Total = count(),
    Successes = countif(IsRequestSuccess == true),
    Failures = countif(IsRequestSuccess == false)
    by BackendUrl
| order by Failures desc

ApiManagementGatewayLogs
| where TimeGenerated > ago(30d)
| where BackendUrl contains "appserviceenvironment.us"
| summarize 
    Total = count(),
    Failures = countif(IsRequestSuccess == false),
    FailRate = round(countif(IsRequestSuccess == false) * 100.0 / count(), 2)
    by bin(TimeGenerated, 1d)
| order by TimeGenerated asc
| render timechart
