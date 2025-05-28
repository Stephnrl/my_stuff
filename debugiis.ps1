try {
    $response = Invoke-WebRequest -Uri "http://localhost:94/workbookloader/api/version" -UseBasicParsing -TimeoutSec 10
    Write-Host "Status: $($response.StatusCode)"
    Write-Host "Content: $($response.Content)"
} catch {
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)"
}

try {
    $response = Invoke-WebRequest -Uri "http://localhost:94/workbookloader/api/version" -UseBasicParsing -MaximumRedirection 0
} catch {
    Write-Host "Response: $($_.Exception.Response.StatusCode)"
    Write-Host "Headers: $($_.Exception.Response.Headers)"
}

Get-IISSite | Where-Object {$_.Name -like "*workbook*"} | Select-Object Name, Bindings


try {
    # Skip certificate validation for testing
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    $response = Invoke-WebRequest -Uri "https://localhost:94/workbookloader/api/version" -UseBasicParsing -TimeoutSec 10
    Write-Host "HTTPS Status: $($response.StatusCode)"
    Write-Host "HTTPS Content: $($response.Content)"
} catch {
    Write-Host "HTTPS Error: $($_.Exception.Message)"
}


Get-IISSite | Select-Object Name, State, @{Name="Bindings";Expression={$_.Bindings | ForEach-Object {"$($_.Protocol):$($_.BindingInformation)"}}}


Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=(Get-Date).AddHours(-1)} | 
    Where-Object {$_.ProviderName -like "*IIS*" -or $_.ProviderName -like "*ASP.NET*" -or $_.Message -like "*workbook*"} | 
    Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message | Format-List

$site = Get-IISSite | Where-Object {$_.Applications.VirtualDirectories.PhysicalPath -like "*workbook*"}
if ($site) {
    Write-Host "Site: $($site.Name)"
    Write-Host "Physical Path: $($site.Applications[0].VirtualDirectories[0].PhysicalPath)"
    Get-ChildItem $site.Applications[0].VirtualDirectories[0].PhysicalPath -ErrorAction SilentlyContinue
}


# Look for stdout logs (ASP.NET Core apps log here by default)
Get-ChildItem "D:\Sites\workbookloader\" -Recurse -Filter "*stdout*" | Sort-Object LastWriteTime -Descending | Select-Object -First 3

# Also check for any .log files
Get-ChildItem "D:\Sites\workbookloader\" -Recurse -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# Get complete application shutdown events
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-1)} | 
    Where-Object {$_.Message -like "*workbook*" -or $_.Message -like "*APPHOST*"} | 
    Select-Object TimeCreated, Message | Format-List


# Verify deployment files exist
Get-ChildItem "D:\Sites\workbookloader\" | Select-Object Name, Length, LastWriteTime
# Look for key files
Test-Path "D:\Sites\workbookloader\appsettings.json"
Test-Path "D:\Sites\workbookloader\web.config"
Get-ChildItem "D:\Sites\workbookloader\*.dll" | Select-Object Name -First 5


# Navigate to app directory and try to run directly
cd "D:\Sites\workbookloader\"
# Look for the main executable
Get-ChildItem "*.exe" | Select-Object Name



# Look for more specific error details in the last hour
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-1)} | 
    Where-Object {$_.Message -like "*workbook*" -or $_.Message -like "*APPHOST*" -or $_.LevelDisplayName -eq "Error"} | 
    Select-Object TimeCreated, LevelDisplayName, Id, Message | 
    Sort-Object TimeCreated | Format-Table -Wrap

# Also check System log for IIS Worker Process issues
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-1)} | 
    Where-Object {$_.Message -like "*w3wp*" -or $_.Message -like "*IIS*"} | 
    Select-Object TimeCreated, LevelDisplayName, Message | Format-List


# Import IIS module and check app pool configuration
Import-Module WebAdministration
Get-IISAppPool -Name "workbookloader" | Select-Object Name, State, ProcessModel, Recycling
