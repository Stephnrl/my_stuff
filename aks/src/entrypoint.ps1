#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Entrypoint for the AKS Safe Upgrade composite action.
    Imports the AKSUpgrade module, reads action inputs from env vars, and runs.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Import the module ──
$modulePath = Join-Path $PSScriptRoot '..' 'AKSUpgrade'
Import-Module $modulePath -Force -Verbose:$false

# ── Read inputs from environment ──
$params = @{
    ResourceGroupName     = $env:INPUT_RESOURCE_GROUP
    ClusterName           = $env:INPUT_CLUSTER_NAME
    TargetVersion         = $env:INPUT_TARGET_VERSION
    MaxSurge              = [int]($env:INPUT_MAX_SURGE ?? '1')
    ValidationWaitSeconds = [int]($env:INPUT_VALIDATION_WAIT ?? '120')
}

if ($env:INPUT_FAIL_ON_WORKLOAD_ISSUES -eq 'true') {
    $params['FailOnWorkloadIssues'] = $true
}

# ── Log configuration ──
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  AKS Upgrade Action" -ForegroundColor Cyan
Write-Host "  Resource Group:     $($params.ResourceGroupName)" -ForegroundColor Cyan
Write-Host "  Cluster:            $($params.ClusterName)" -ForegroundColor Cyan
Write-Host "  Target Version:     $($params.TargetVersion)" -ForegroundColor Cyan
Write-Host "  Max Surge:          $($params.MaxSurge)" -ForegroundColor Cyan
Write-Host "  Validation Wait:    $($params.ValidationWaitSeconds)s" -ForegroundColor Cyan
Write-Host "  Fail on Workloads:  $($params.ContainsKey('FailOnWorkloadIssues'))" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# ── Execute ──
try {
    Invoke-AKSClusterUpgrade @params
}
catch {
    Write-Host "::error::AKS upgrade failed: $_"
    exit 1
}
