$vsInstaller = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$installPath = "D:\Program Files\Microsoft Visual Studio\2022\Professional"
Start-Process -FilePath $vsInstaller -ArgumentList "modify", "--installPath `"$installPath`"", "--add Microsoft.VisualStudio.Workload.Office", "--includeRecommended", "--passive", "--norestart" -Wait
Write-Host "Modification complete. Checking for files..." -ForegroundColor Cyan
