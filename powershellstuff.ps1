Write-Host "=== .NET Framework Registry Check ==="
# Check installed .NET Framework versions
Get-ChildItem "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" | 
  Get-ItemProperty | Select-Object PSChildName, Release, Version

Write-Host "`n=== .NET Core/5+ Check ==="
try {
  dotnet --list-runtimes
} catch {
  Write-Host ".NET CLI not available"
}


Write-Host "=== .NET Framework Registry Check ==="
# Check installed .NET Framework versions
Get-ChildItem "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" | 
  Get-ItemProperty | Select-Object PSChildName, Release, Version

Write-Host "`n=== .NET Core/5+ Check ==="
try {
  dotnet --list-runtimes
} catch {
  Write-Host ".NET CLI not available"
}
