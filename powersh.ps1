#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simple Azure IP conflict checker using Azure CLI and basic pattern matching.

.PARAMETER NewSubnetCidr
    The CIDR block you want to validate (e.g., "10.42.189.0/24")

.PARAMETER CheckAllSubscriptions
    Switch to check across all accessible subscriptions

.EXAMPLE
    .\Simple-IPCheck.ps1 -NewSubnetCidr "10.42.189.0/24"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$NewSubnetCidr,
    
    [Parameter(Mandatory = $false)]
    [switch]$CheckAllSubscriptions
)

Write-Host "=== Simple Azure IP Conflict Checker ===" -ForegroundColor Green
Write-Host "Checking for conflicts with: $NewSubnetCidr" -ForegroundColor Yellow

# Extract the network portion for basic comparison
$newNetwork = $NewSubnetCidr.Split('/')[0]
$newPrefix = [int]$NewSubnetCidr.Split('/')[1]
$newOctets = $newNetwork.Split('.')

# Create search patterns based on prefix length
$searchPatterns = @()
if ($newPrefix -ge 8) {
    $searchPatterns += "$($newOctets[0]).*"
}
if ($newPrefix -ge 16) {
    $searchPatterns += "$($newOctets[0]).$($newOctets[1]).*"
}
if ($newPrefix -ge 24) {
    $searchPatterns += "$($newOctets[0]).$($newOctets[1]).$($newOctets[2]).*"
}

Write-Host "Search patterns: $($searchPatterns -join ', ')" -ForegroundColor Gray

# Get subscriptions to check
if ($CheckAllSubscriptions) {
    Write-Host "Getting all subscriptions..." -ForegroundColor Yellow
    $subscriptions = az account list --query "[?state=='Enabled'].id" --output tsv
}
else {
    $currentSub = az account show --query "id" --output tsv
    $subscriptions = @($currentSub)
}

Write-Host "Checking $($subscriptions.Count) subscription(s)..." -ForegroundColor Cyan

$allConflicts = @()

foreach ($subId in $subscriptions) {
    Write-Host "  Subscription: $subId" -ForegroundColor Gray
    
    # Set subscription context
    az account set --subscription $subId | Out-Null
    
    # Get all VNets and their address spaces
    $vnetsJson = az network vnet list --query "[].{name:name, resourceGroup:resourceGroup, addressPrefixes:addressSpace.addressPrefixes, subnets:subnets[].{name:name, addressPrefix:addressPrefix}}" --output json
    
    if ($vnetsJson) {
        $vnets = $vnetsJson | ConvertFrom-Json
        
        foreach ($vnet in $vnets) {
            # Check VNet address spaces
            foreach ($addressPrefix in $vnet.addressPrefixes) {
                if ($addressPrefix) {
                    # Simple overlap detection
                    $existingNetwork = $addressPrefix.Split('/')[0]
                    $existingPrefix = [int]$addressPrefix.Split('/')[1]
                    
                    # Check for potential conflicts
                    $isConflict = $false
                    
                    # Exact match
                    if ($addressPrefix -eq $NewSubnetCidr) {
                        $isConflict = $true
                    }
                    # Check if new subnet falls within existing range
                    elseif ($existingPrefix -le $newPrefix) {
                        $existingOctets = $existingNetwork.Split('.')
                        $octetsToCheck = [math]::Floor($existingPrefix / 8)
                        
                        $match = $true
                        for ($i = 0; $i -lt $octetsToCheck -and $i -lt 4; $i++) {
                            if ($existingOctets[$i] -ne $newOctets[$i]) {
                                $match = $false
                                break
                            }
                        }
                        
                        if ($match -and $octetsToCheck -lt 4) {
                            # Check partial octet if needed
                            $remainingBits = $existingPrefix % 8
                            if ($remainingBits -gt 0) {
                                $existingOctet = [int]$existingOctets[$octetsToCheck]
                                $newOctet = [int]$newOctets[$octetsToCheck]
                                $mask = (255 -shl (8 - $remainingBits)) -band 255
                                if (($existingOctet -band $mask) -eq ($newOctet -band $mask)) {
                                    $match = $true
                                }
                                else {
                                    $match = $false
                                }
                            }
                        }
                        
                        if ($match) {
                            $isConflict = $true
                        }
                    }
                    
                    if ($isConflict) {
                        $allConflicts += [PSCustomObject]@{
                            SubscriptionId = $subId
                            ResourceGroup = $vnet.resourceGroup
                            VNetName = $vnet.name
                            Type = "VNet Address Space"
                            ConflictingRange = $addressPrefix
                            ProposedRange = $NewSubnetCidr
                        }
                    }
                }
            }
            
            # Check individual subnets
            if ($vnet.subnets) {
                foreach ($subnet in $vnet.subnets) {
                    if ($subnet.addressPrefix) {
                        # Simple conflict check for subnets
                        if ($subnet.addressPrefix -eq $NewSubnetCidr -or 
                            $subnet.addressPrefix.Split('/')[0] -eq $newNetwork) {
                            
                            $allConflicts += [PSCustomObject]@{
                                SubscriptionId = $subId
                                ResourceGroup = $vnet.resourceGroup
                                VNetName = $vnet.name
                                Type = "Subnet: $($subnet.name)"
                                ConflictingRange = $subnet.addressPrefix
                                ProposedRange = $NewSubnetCidr
                            }
                        }
                    }
                }
            }
        }
    }
}

# Display results
Write-Host ""
if ($allConflicts.Count -eq 0) {
    Write-Host "✅ No obvious conflicts detected!" -ForegroundColor Green
    Write-Host "The subnet $NewSubnetCidr appears safe to deploy." -ForegroundColor Green
    Write-Host ""
    Write-Host "Note: This is a basic check. For production deployments," -ForegroundColor Yellow
    Write-Host "consider using more sophisticated CIDR overlap detection." -ForegroundColor Yellow
}
else {
    Write-Host "⚠️  POTENTIAL CONFLICTS DETECTED: $($allConflicts.Count) overlapping resources found!" -ForegroundColor Red
    Write-Host ""
    
    $allConflicts | Format-Table -Property SubscriptionId, ResourceGroup, VNetName, Type, ConflictingRange -AutoSize
    
    Write-Host ""
    Write-Host "❌ Do not proceed with deployment until conflicts are resolved!" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Proposed subnet: $NewSubnetCidr" -ForegroundColor White
Write-Host "Subscriptions checked: $($subscriptions.Count)" -ForegroundColor White
Write-Host "Potential conflicts: $($allConflicts.Count)" -ForegroundColor White
