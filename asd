$vsInstaller = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$installPath = "D:\Program Files\Microsoft Visual Studio\2022\Professional"
Start-Process -FilePath $vsInstaller -ArgumentList "modify", "--installPath `"$installPath`"", "--add Microsoft.VisualStudio.Workload.Office", "--includeRecommended", "--passive", "--norestart" -Wait
Write-Host "Modification complete. Checking for files..." -ForegroundColor Cyan


$officeTargets = "D:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Microsoft\VisualStudio\v17.0\OfficeTools\Microsoft.VisualStudio.Tools.Office.targets"
if (Test-Path $officeTargets) {
    Write-Host "SUCCESS: Office Targets found at $officeTargets" -ForegroundColor Green
} else {
    Write-Host "STILL MISSING: The workload installation may have failed." -ForegroundColor Red
}
