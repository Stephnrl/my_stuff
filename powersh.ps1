#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Checks for IP address conflicts across Azure VNets before creating a new subnet.

.DESCRIPTION
    This script validates that a proposed subnet CIDR doesn't conflict with existing
    VNets and subnets across one or all Azure subscriptions.

.PARAMETER NewSubnetCidr
    The CIDR block you want to validate (e.g., "10.42.189.0/24")

.PARAMETER CheckAllSubscriptions
    Switch to check across all accessible subscriptions instead of just the current one

.PARAMETER SubscriptionId
    Specific subscription ID to check (optional, uses current if not specified)

.PARAMETER OutputFormat
    Output format: Table, JSON, or CSV (default: Table)

.EXAMPLE
    .\Check-AzureIPConflicts.ps1 -NewSubnetCidr "10.42.189.0/24"
    
.EXAMPLE
    .\Check-AzureIPConflicts.ps1 -NewSubnetCidr "10.42.189.0/24" -CheckAllSubscriptions

.EXAMPLE
    .\Check-AzureIPConflicts.ps1 -NewSubnetCidr "10.42.189.0/24" -OutputFormat JSON
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$NewSubnetCidr,
    
    [Parameter(Mandatory = $false)]
    [switch]$CheckAllSubscriptions,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Table", "JSON", "CSV")]
    [string]$OutputFormat = "Table"
)

# Function to check if two CIDR blocks overlap
function Test-CIDROverlap {
    param(
        [string]$Cidr1,
        [string]$Cidr2
    )
    
    try {
        # Parse CIDR blocks
        $network1 = [ipaddress]($Cidr1.Split('/')[0])
        $prefix1 = [int]($Cidr1.Split('/')[1])
        $network2 = [ipaddress]($Cidr2.Split('/')[0])
        $prefix2 = [int]($Cidr2.Split('/')[1])
        
        # Convert to network addresses
        $mask1 = [ipaddress](([math]::Pow(2, 32) - [math]::Pow(2, (32 - $prefix1))) -band 0xFFFFFFFF)
        $mask2 = [ipaddress](([math]::Pow(2, 32) - [math]::Pow(2, (32 - $prefix2))) -band 0xFFFFFFFF)
        
        $networkAddr1 = [ipaddress]($network1.Address -band $mask1.Address)
        $networkAddr2 = [ipaddress]($network2.Address -band $mask2.Address)
        
        # Calculate broadcast addresses
        $broadcast1 = [ipaddress]($networkAddr1.Address -bor (-bnot $mask1.Address -band 0xFFFFFFFF))
        $broadcast2 = [ipaddress]($networkAddr2.Address -bor (-bnot $mask2.Address -band 0xFFFFFFFF))
        
        # Check for overlap
        return (
            ($networkAddr1.Address -le $networkAddr2.Address -and $broadcast1.Address -ge $networkAddr2.Address) -or
            ($networkAddr2.Address -le $networkAddr1.Address -and $broadcast2.Address -ge $networkAddr1.Address)
        )
    }
    catch {
        Write-Warning "Failed to parse CIDR blocks: $Cidr1, $Cidr2. Error: $($_.Exception.Message)"
        return $false
    }
}

# Function to get all VNets from a subscription
function Get-VNetsFromSubscription {
    param([string]$SubId)
    
    Write-Host "Checking subscription: $SubId" -ForegroundColor Cyan
    
    try {
        # Set the subscription context
        az account set --subscription $SubId | Out-Null
        
        # Get all VNets in the subscription
        $vnetsJson = az network vnet list --query "[].{name:name, resourceGroup:resourceGroup, addressPrefixes:addressSpace.addressPrefixes, location:location, subnets:subnets[].{name:name, addressPrefix:addressPrefix}}" --output json
        
        if ($vnetsJson) {
            $vnets = $vnetsJson | ConvertFrom-Json
            
            $results = @()
            foreach ($vnet in $vnets) {
                # Check VNet address spaces
                foreach ($addressPrefix in $vnet.addressPrefixes) {
                    $results += [PSCustomObject]@{
                        SubscriptionId = $SubId
                        ResourceGroup = $vnet.resourceGroup
                        VNetName = $vnet.name
                        ResourceType = "VNet Address Space"
                        ResourceName = $vnet.name
                        AddressPrefix = $addressPrefix
                        Location = $vnet.location
                    }
                }
                
                # Check individual subnets
                if ($vnet.subnets) {
                    foreach ($subnet in $vnet.subnets) {
                        if ($subnet.addressPrefix) {
                            $results += [PSCustomObject]@{
                                SubscriptionId = $SubId
                                ResourceGroup = $vnet.resourceGroup
                                VNetName = $vnet.name
                                ResourceType = "Subnet"
                                ResourceName = "$($vnet.name)/$($subnet.name)"
                                AddressPrefix = $subnet.addressPrefix
                                Location = $vnet.location
                            }
                        }
                    }
                }
            }
            return $results
        }
        return @()
    }
    catch {
        Write-Warning "Failed to query subscription $SubId`: $($_.Exception.Message)"
        return @()
    }
}

# Main script execution
Write-Host "=== Azure IP Conflict Checker ===" -ForegroundColor Green
Write-Host "Checking for conflicts with: $NewSubnetCidr" -ForegroundColor Yellow
Write-Host ""

# Validate the new subnet CIDR format
try {
    $null = [ipaddress]($NewSubnetCidr.Split('/')[0])
    $null = [int]($NewSubnetCidr.Split('/')[1])
}
catch {
    Write-Error "Invalid CIDR format: $NewSubnetCidr. Please use format like '10.42.189.0/24'"
    exit 1
}

# Check if Azure CLI is logged in
$currentAccount = az account show --output json 2>$null
if (-not $currentAccount) {
    Write-Error "Please run 'az login' first to authenticate with Azure."
    exit 1
}

$currentAccountObj = $currentAccount | ConvertFrom-Json
Write-Host "Current account: $($currentAccountObj.user.name)" -ForegroundColor Green

# Determine which subscriptions to check
$subscriptionsToCheck = @()

if ($CheckAllSubscriptions) {
    Write-Host "Getting all accessible subscriptions..." -ForegroundColor Yellow
    $allSubs = az account list --query "[?state=='Enabled'].{id:id, name:name}" --output json | ConvertFrom-Json
    $subscriptionsToCheck = $allSubs.id
    Write-Host "Found $($subscriptionsToCheck.Count) enabled subscriptions" -ForegroundColor Green
}
elseif ($SubscriptionId) {
    $subscriptionsToCheck = @($SubscriptionId)
}
else {
    $subscriptionsToCheck = @($currentAccountObj.id)
}

Write-Host ""

# Collect all existing networks
$allNetworks = @()
$subscriptionCount = 0

foreach ($subId in $subscriptionsToCheck) {
    $subscriptionCount++
    Write-Progress -Activity "Scanning subscriptions" -Status "Subscription $subscriptionCount of $($subscriptionsToCheck.Count)" -PercentComplete (($subscriptionCount / $subscriptionsToCheck.Count) * 100)
    
    $networks = Get-VNetsFromSubscription -SubId $subId
    $allNetworks += $networks
    
    Write-Host "  Found $($networks.Count) network resources in subscription $subId" -ForegroundColor Gray
}

Write-Progress -Activity "Scanning subscriptions" -Completed

Write-Host ""
Write-Host "Total network resources found: $($allNetworks.Count)" -ForegroundColor Green
Write-Host ""

# Check for conflicts
Write-Host "Checking for IP conflicts..." -ForegroundColor Yellow
$conflicts = @()

foreach ($network in $allNetworks) {
    if (Test-CIDROverlap -Cidr1 $NewSubnetCidr -Cidr2 $network.AddressPrefix) {
        $conflicts += $network
    }
}

# Display results
Write-Host ""
if ($conflicts.Count -eq 0) {
    Write-Host "✅ SUCCESS: No IP conflicts detected!" -ForegroundColor Green
    Write-Host "The subnet $NewSubnetCidr is safe to deploy." -ForegroundColor Green
}
else {
    Write-Host "❌ CONFLICTS DETECTED: $($conflicts.Count) overlapping resources found!" -ForegroundColor Red
    Write-Host ""
    
    switch ($OutputFormat) {
        "Table" {
            $conflicts | Format-Table -Property SubscriptionId, ResourceGroup, VNetName, ResourceType, ResourceName, AddressPrefix, Location -AutoSize
        }
        "JSON" {
            $conflicts | ConvertTo-Json -Depth 3
        }
        "CSV" {
            $conflicts | ConvertTo-Csv -NoTypeInformation
        }
    }
}

# Summary
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Validated CIDR: $NewSubnetCidr" -ForegroundColor White
Write-Host "Subscriptions checked: $($subscriptionsToCheck.Count)" -ForegroundColor White
Write-Host "Total networks scanned: $($allNetworks.Count)" -ForegroundColor White
Write-Host "Conflicts found: $($conflicts.Count)" -ForegroundColor White

if ($conflicts.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠️  Do not proceed with deployment until conflicts are resolved!" -ForegroundColor Red
    exit 1
}
else {
    Write-Host ""
    Write-Host "✅ Safe to proceed with subnet deployment!" -ForegroundColor Green
    exit 0
}
