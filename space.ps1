Get-ChildItem C:\ -Recurse -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.Length -gt 100MB } | 
    Sort-Object Length -Descending | 
    Select-Object FullName, @{Name="SizeGB";Expression={[math]::Round($_.Length/1GB,3)}}, LastWriteTime |
    Format-Table -AutoSize


Get-ChildItem C:\ -Directory | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue | 
             Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Folder = $_.Name
        SizeGB = [math]::Round($size / 1GB, 2)
        SizeMB = [math]::Round($size / 1MB, 2)
    }
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize



# Find directories with "log" in the name that are large
Get-ChildItem C:\ -Recurse -Directory -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -like "*log*" } | 
    ForEach-Object {
        $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue | 
                 Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            LogDirectory = $_.FullName
            SizeGB = [math]::Round($size / 1GB, 2)
            FileCount = (Get-ChildItem $_.FullName -File -Recurse -ErrorAction SilentlyContinue).Count
        }
    } | Where-Object { $_.SizeGB -gt 0.1 } | Sort-Object SizeGB -Descending
    

$iisLogPath = "C:\inetpub\logs\LogFiles"
if (Test-Path $iisLogPath) {
    Get-ChildItem $iisLogPath -Recurse -File | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
        Remove-Item -Force
    
    Write-Host "IIS logs older than 30 days removed"
}
