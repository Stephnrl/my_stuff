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









Get-ChildItem "D:\Logs" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue | 
             Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        LogFolder = $_.Name
        Path = $_.FullName
        SizeGB = [math]::Round($size / 1GB, 3)
        SizeMB = [math]::Round($size / 1MB, 1)
        FileCount = (Get-ChildItem $_.FullName -File -Recurse -ErrorAction SilentlyContinue).Count
    }
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize


Get-ChildItem "D:\Logs" -File -Recurse -ErrorAction SilentlyContinue | 
    Sort-Object Length -Descending | 
    Select-Object -First 20 |
    Select-Object Name, Directory, 
        @{Name="SizeMB";Expression={[math]::Round($_.Length/1MB,1)}},
        @{Name="SizeGB";Expression={[math]::Round($_.Length/1GB,3)}},
        LastWriteTime |
    Format-Table -AutoSize

    
