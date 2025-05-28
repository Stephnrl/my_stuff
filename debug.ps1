Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 @{
    Name='Process Name'; Expression={$_.ProcessName}
}, @{
    Name='CPU Time (Minutes)'; Expression={[math]::Round($_.CPU/60,2)}
}, @{
    Name='Memory (MB)'; Expression={[math]::Round($_.WorkingSet/1MB,2)}
}, @{
    Name='Process ID'; Expression={$_.Id}
} | Format-Table -AutoSize



Get-Counter "\Process(*)\% Processor Time" | Select-Object -ExpandProperty CounterSamples | Sort-Object CookedValue -Descending | Select-Object -First 10 @{
    Name='Process'; Expression={($_.InstanceName)}
}, @{
    Name='CPU %'; Expression={[math]::Round($_.CookedValue,2)}
} | Format-Table



Get-WmiObject -Class Win32_PerfRawData_PerfProc_Process | 
    Where-Object {$_.Name -ne "_Total" -and $_.Name -ne "Idle"} |
    Sort-Object PageFileBytes -Descending | 
    Select-Object -First 10 Name, 
    @{Name="Memory MB";Expression={[math]::round($_.WorkingSetSize/1MB,2)}} |
    Format-Table -AutoSize


Get-WmiObject -Query "SELECT * FROM Win32_Process WHERE Name='svchost.exe'" | ForEach-Object {
    $processId = $_.ProcessId
    $services = Get-WmiObject -Query "SELECT * FROM Win32_Service WHERE ProcessId=$processId"
    [PSCustomObject]@{
        ProcessId = $processId
        Services = ($services.Name -join ', ')
        CPU = (Get-Process -Id $processId -ErrorAction SilentlyContinue).CPU
    }
} | Sort-Object CPU -Descending | Format-Table -Wrap




Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 100 | Where-Object {$_.Message -match "Invoke-RemoteDeployment|Test Web Application|RuntimeException|DevTestLabs"} | Select-Object TimeCreated, ProviderName, Message | Format-List


Get-WinEvent -FilterHashtable @{LogName='Windows PowerShell'; Level=2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 50 | Select-Object TimeCreated, Id, Message | Format-List

Get-ChildItem C:\ -Recurse -Name "*deploy*","*error*","*.log" -ErrorAction SilentlyContinue | Where-Object {(Get-Item $_ -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays(-7)} | ForEach-Object {
    Write-Host "Found: $_"
    Get-Content $_ -Tail 10 -ErrorAction SilentlyContinue
}

Get-ChildItem $env:TEMP, "C:\Windows\Temp" -Name "*.log" -ErrorAction SilentlyContinue | Where-Object {(Get-Item "$env:TEMP\$_" -ErrorAction SilentlyContinue).LastWriteTime -gt (Get-Date).AddDays(-7)}

