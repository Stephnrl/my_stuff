# Define the path to your copied file
$vsixPath = "C:\Users\11111111\Documents\InstallerProjects2022.vsix"

# Define the path to the installer (Adjust 'Community' if needed)
$vsixInstaller = "D:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\VSIXInstaller.exe"

# Execute the silent installation
Start-Process -FilePath $vsixInstaller -ArgumentList "/q", "/admin", "`"$vsixPath`"" -Wait
