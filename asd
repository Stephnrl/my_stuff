.\vs_professional.exe --installPath "D:\Program Files\Microsoft Visual Studio\2022\Professional" --add Microsoft.VisualStudio.Workload.ManagedDesktop --passive --norestart --wait


$vsixPath = "C:\Users\11111111\Documents\InstallerProjects2022.vsix"
$vsixInstaller = "D:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\VSIXInstaller.exe"

Start-Process -FilePath $vsixInstaller -ArgumentList "/q", "/admin", "`"$vsixPath`"" -Wait
