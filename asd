Get-ChildItem -Path "D:\Program Files\Microsoft Visual Studio\2022" -Filter "DisableOutOfProcBuild.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
