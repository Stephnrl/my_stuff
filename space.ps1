Get-ChildItem C:\ -Recurse -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.Length -gt 100MB } | 
    Sort-Object Length -Descending | 
    Select-Object FullName, @{Name="SizeGB";Expression={[math]::Round($_.Length/1GB,3)}}, LastWriteTime |
    Format-Table -AutoSize
