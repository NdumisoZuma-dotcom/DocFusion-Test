# ================================
# Azure Infra Verification Script
# ================================

param (
    [string]$resourceGroupName,
    [string]$resourcePrefix
)

Write-Host "`n🔍 Verifying Azure infrastructure for prefix: $resourcePrefix" -ForegroundColor Cyan

# Get resource names
$storageAccountName = ("{0}sa" -f $resourcePrefix).ToLower()
$vnetName           = "$resourcePrefix-vnet"
$nsgName            = "$resourcePrefix-nsg"
$webAppName         = "$resourcePrefix-webapp"
$planName           = "$resourcePrefix-plan"
$appInsightsName    = "$resourcePrefix-appinsights"

# Check resources
$resources = @(
    $vnetName, $nsgName, $storageAccountName, $webAppName, $planName, $appInsightsName
)

foreach ($res in $resources) {
    $exists = az resource show --name $res --resource-group $resourceGroupName --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ $res exists." -ForegroundColor Green
    } else {
        Write-Host "❌ $res NOT found!" -ForegroundColor Red
    }
}

# Check NSG rules
Write-Host "`n🔐 Checking NSG rules for: $nsgName" -ForegroundColor Cyan

$nsgRules = az network nsg rule list --nsg-name $nsgName --resource-group $resourceGroupName | ConvertFrom-Json

$allowRule = $nsgRules | Where-Object { $_.name -eq 'Allow-HTTPS-From-AllowedIP' }
$denyRule  = $nsgRules | Where-Object { $_.name -eq 'Deny-All-Inbound' }

if ($allowRule -and $allowRule.properties.destinationPortRange -eq "443") {
    Write-Host "✅ Allow rule on port 443 exists and is correctly configured." -ForegroundColor Green
} else {
    Write-Host "❌ Allow rule for port 443 is missing or misconfigured." -ForegroundColor Red
}

if ($denyRule) {
    Write-Host "✅ Deny-All-Inbound rule exists." -ForegroundColor Green
} else {
    Write-Host "❌ Deny-All-Inbound rule is missing." -ForegroundColor Red
}

# Check NSG association
$vnet = az network vnet show --name $vnetName --resource-group $resourceGroupName | ConvertFrom-Json
$subnet = $vnet.properties.subnets | Where-Object { $_.name -eq 'storageSubnet' }

if ($subnet.properties.networkSecurityGroup.id -match $nsgName) {
    Write-Host "✅ NSG is correctly associated with storageSubnet." -ForegroundColor Green
} else {
    Write-Host "❌ NSG is NOT associated with storageSubnet." -ForegroundColor Red
}

Write-Host "`n✅ Verification complete.`n" -ForegroundColor Cyan
