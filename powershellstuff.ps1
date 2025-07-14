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


Write-Host "=== Testing System.IO.Pipes Types ==="

# Test various pipe-related types
$types = @(
  'System.IO.Pipes.PipeException',
  'System.IO.Pipes.NamedPipeServerStream',
  'System.IO.Pipes.NamedPipeClientStream',
  'System.IO.IOException'
)

foreach ($type in $types) {
  try {
    $typeObj = [type]$type
    Write-Host "✅ $type - Available"
  } catch {
    Write-Host "❌ $type - NOT Available: $($_.Exception.Message)"
  }
}

Write-Host "`n=== Assembly Loading Test ==="
try {
  Add-Type -AssemblyName System.Core
  Write-Host "✅ System.Core assembly loaded successfully"
} catch {
  Write-Host "❌ Failed to load System.Core: $($_.Exception.Message)"
}
