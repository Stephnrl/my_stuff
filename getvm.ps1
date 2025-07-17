function Get-VulnerabilityReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ACRRegistryName,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = "$PSScriptRoot\Data\images.json",
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "vulnerability_report.json"
    )
    
    begin {
        Write-Host "🔍 Starting vulnerability scan for ACR: $ACRRegistryName" -ForegroundColor Cyan
    }
    
    process {
        try {
            # Load configuration to get repositories
            $Config = Get-ImageConfiguration -ConfigPath $ConfigPath
            $Repositories = $Config.images.repository | Sort-Object -Unique
            
            # KQL query for vulnerability data
            $Query = @"
SecurityResources
| where type == 'microsoft.security/assessments'
| where properties.displayName contains 'Azure registry container images should have vulnerabilities resolved'
| summarize by assessmentKey=name
| join kind=inner (
    securityresources
    | where type == 'microsoft.security/assessments/subassessments'
    | extend assessmentKey = extract('.*assessments/(.+?)/.*',1,  id)
) on assessmentKey
| project assessmentKey, subassessmentKey=name, id, properties, resourceGroup, subscriptionId, tenantId
| extend
    description = properties.description,
    displayName = properties.displayName,
    resourceId = properties.resourceDetails.id,
    resourceSource = properties.resourceDetails.source,
    category = properties.category,
    severity = properties.status.severity,
    code = properties.status.code,
    timeGenerated = properties.timeGenerated,
    remediation = properties.remediation,
    impact = properties.impact,
    vulnId = properties.id,
    additionalData = todynamic(properties.additionalData)
| where isnotempty(additionalData.artifactDetails)
| extend
    registryName = tostring(additionalData.artifactDetails.registryHost),
    repository = tostring(additionalData.artifactDetails.repositoryName),
    imageDigest = tostring(additionalData.artifactDetails.digest)
| where registryName contains '$ACRRegistryName'
| project registryName, repository, imageDigest, severity, displayName, description, vulnId, timeGenerated, remediation, impact
| order by repository asc, severity desc, timeGenerated desc
"@
            
            Write-Host "📊 Executing Azure Resource Graph query..." -ForegroundColor Yellow
            $VulnerabilityData = Search-AzGraph -Query $Query
            
            if (-not $VulnerabilityData) {
                Write-Host "ℹ️  No vulnerability data found" -ForegroundColor Yellow
                return @{
                    CriticalCount = 0
                    HighCount = 0
                    MediumCount = 0
                    LowCount = 0
                    TotalCount = 0
                    RepositorySummary = @()
                    DetailedResults = @()
                }
            }
            
            # Process results
            $DetailedResults = $VulnerabilityData | ForEach-Object {
                [PSCustomObject]@{
                    Registry = $_.registryName
                    Repository = $_.repository
                    ImageDigest = $_.imageDigest
                    Severity = $_.severity
                    VulnerabilityName = $_.displayName
                    Description = $_.description
                    VulnId = $_.vulnId
                    TimeGenerated = $_.timeGenerated
                    Remediation = $_.remediation
                    Impact = $_.impact
                }
            }
            
            # Calculate summary statistics
            $CriticalCount = ($DetailedResults | Where-Object { $_.Severity -eq 'High' }).Count
            $HighCount = ($DetailedResults | Where-Object { $_.Severity -eq 'Medium' }).Count
            $MediumCount = ($DetailedResults | Where-Object { $_.Severity -eq 'Low' }).Count
            $LowCount = ($DetailedResults | Where-Object { $_.Severity -eq 'Informational' }).Count
            
            # Repository summary
            $RepositorySummary = $DetailedResults | Group-Object -Property Repository | ForEach-Object {
                $RepoVulns = $_.Group
                [PSCustomObject]@{
                    Repository = $_.Name
                    Critical = ($RepoVulns | Where-Object { $_.Severity -eq 'High' }).Count
                    High = ($RepoVulns | Where-Object { $_.Severity -eq 'Medium' }).Count
                    Medium = ($RepoVulns | Where-Object { $_.Severity -eq 'Low' }).Count
                    Low = ($RepoVulns | Where-Object { $_.Severity -eq 'Informational' }).Count
                    Total = $RepoVulns.Count
                }
            }
            
            # Export results
            $Results = @{
                CriticalCount = $CriticalCount
                HighCount = $HighCount
                MediumCount = $MediumCount
                LowCount = $LowCount
                TotalCount = $DetailedResults.Count
                RepositorySummary = $RepositorySummary
                DetailedResults = $DetailedResults
                GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            $Results | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host "📄 Vulnerability report saved to: $OutputPath" -ForegroundColor Green
            
            # Display summary
            Write-Host "📊 Vulnerability Summary:" -ForegroundColor Cyan
            Write-Host "  Critical: $CriticalCount" -ForegroundColor Red
            Write-Host "  High: $HighCount" -ForegroundColor Yellow
            Write-Host "  Medium: $MediumCount" -ForegroundColor Yellow
            Write-Host "  Low: $LowCount" -ForegroundColor Green
            Write-Host "  Total: $($DetailedResults.Count)" -ForegroundColor White
            
            return $Results
        }
        catch {
            Write-Error "Vulnerability scan failed: $($_.Exception.Message)"
            throw
        }
    }
}
