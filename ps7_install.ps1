$url = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.0-win-x64.msi"
$output = "$env:TEMP\PowerShell-7.4.0-win-x64.msi"
Invoke-WebRequest -Uri $url -OutFile $output
Start-Process msiexec.exe -ArgumentList "/i $output /quiet" -Wait
pwsh --version
