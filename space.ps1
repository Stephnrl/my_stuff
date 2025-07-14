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
