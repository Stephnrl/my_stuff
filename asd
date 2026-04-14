Get-ChildItem -Path "D:\Program Files" -Filter "VSIXInstaller.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
