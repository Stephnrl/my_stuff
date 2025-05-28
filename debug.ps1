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
