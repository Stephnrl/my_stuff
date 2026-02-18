---
# -------------------------------------------------------
# Visual Studio Build Tools - Role Defaults
# Override per-role invocation in site.yml
# -------------------------------------------------------

# Label used for idempotency checks and install paths
# Change per invocation if installing multiple versions
vs_install_label: "vs2022"

# VS installer bootstrap URL
vs_installer_url: "https://aka.ms/vs/17/release/vs_buildtools.exe"

# MSBuild major version — used to locate msbuild.exe after install
vs_version_major: 17

# VS installer download destination
vs_installer_dest: "C:\\Windows\\Temp\\vs_buildtools_{{ vs_install_label }}.exe"

# Where VS Build Tools gets installed
# VS supports side-by-side via --installPath
vs_install_path: "C:\\BuildTools\\{{ vs_install_label }}"

# Workloads to install (IDs from VS docs)
vs_workloads:
  - Microsoft.VisualStudio.Workload.MSBuildTools
  - Microsoft.VisualStudio.Workload.NetCoreBuildTools

# Individual components to install
vs_components:
  - Microsoft.Net.Component.4.8.SDK
  - Microsoft.NetCore.Component.SDK
  - Microsoft.VisualStudio.Component.NuGet.BuildTools
  - Microsoft.Net.Component.8.0.SDK
  - Microsoft.Net.Component.8.0.TargetingPack

# If true, will patch system PATH for this MSBuild version
vs_register_msbuild_path: true

# Timeout for VS installer in seconds (it can be slow)
vs_install_timeout: 3600

# Installer log path
vs_install_log: "C:\\Windows\\Temp\\vs_install_{{ vs_install_label }}.log"
