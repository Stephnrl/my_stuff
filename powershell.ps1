Get-ChildItem -Path "C:\" -Include "*.log", "*.txt" -Recurse -ErrorAction SilentlyContinue | 
Sort-Object Length -Descending | 
Select-Object Name, Directory, @{Name="Size(MB)";Expression={[math]::Round($_.Length/1MB,2)}} -First 20



$logPatterns = @("*.log", "*.txt", "*.out", "*.trace", "*.audit")
Get-ChildItem -Path "C:\" -Include $logPatterns -Recurse -ErrorAction SilentlyContinue | 
Where-Object {$_.Length -gt 10MB} | 
Sort-Object Length -Descending | 
Format-Table Name, Directory, @{Name="Size(GB)";Expression={[math]::Round($_.Length/1GB,3)}} -AutoSize



$logPaths = @(
    "C:\Windows\Logs",
    "C:\inetpub\logs",
    "C:\ProgramData\Microsoft\Windows\WER",
    "C:\Windows\System32\winevt\Logs"
)

foreach ($path in $logPaths) {
    if (Test-Path $path) {
        Write-Host "=== $path ===" -ForegroundColor Green
        Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | 
        Sort-Object Length -Descending | 
        Select-Object Name, @{Name="Size(MB)";Expression={[math]::Round($_.Length/1MB,2)}} -First 10
    }
}



Get-ChildItem -Path "D:\" -Directory | 
ForEach-Object {
    $size = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | 
             Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Directory = $_.Name
        SizeGB = [math]::Round($size / 1GB, 2)
    }
} | Sort-Object SizeGB -Descending
