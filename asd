$vsSetup = "D:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\vs_setup.exe"
Start-Process -FilePath "vs_professional.exe" -ArgumentList "modify", "--installPath `"D:\Program Files\Microsoft Visual Studio\2022\Professional`"", "--add Microsoft.VisualStudio.Workload.Office", "--includeRecommended", "--passive", "--norestart", "--wait" -Wait
