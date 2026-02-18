---
# Known MSBuild paths per VS major version
# Used for PATH registration and validation
vs_msbuild_paths:
  "15": "MSBuild\\15.0\\Bin"
  "16": "MSBuild\\Current\\Bin"
  "17": "MSBuild\\Current\\Bin"

# Computed full path to msbuild.exe
vs_msbuild_exe: "{{ vs_install_path }}\\{{ vs_msbuild_paths[vs_version_major | string] }}\\MSBuild.exe"

# Sentinel file written after a successful install
# Used for idempotency — skips reinstall if present
vs_install_sentinel: "C:\\BuildTools\\.installed_{{ vs_install_label }}"
