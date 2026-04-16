$vsInstaller = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
$installPath = "D:\Program Files\Microsoft Visual Studio\2022\Professional"
Start-Process -FilePath $vsInstaller -ArgumentList "modify", "--installPath `"$installPath`"", "--add Microsoft.VisualStudio.Workload.NativeDesktop", "--includeRecommended", "--passive", "--norestart" -Wait
Write-Host "C++ Build Tools installation complete." -ForegroundColor Cyan


$msvcPath = "D:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC"

if (Test-Path $msvcPath) {
    Write-Host "SUCCESS: MSVC Tools folder now exists!" -ForegroundColor Green
    Get-ChildItem $msvcPath # This should show a version number folder like 14.4x.xxxx
} else {
    Write-Host "STILL MISSING: The workload might not have installed correctly." -ForegroundColor Red
}
