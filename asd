---
- name: "[{{ vs_install_label }}] Confirm MSBuild.exe is present"
  ansible.windows.win_stat:
    path: "{{ vs_msbuild_exe }}"
  register: msbuild_check

- name: "[{{ vs_install_label }}] Verify MSBuild version matches expected major"
  ansible.windows.win_shell: |
    $ver = & "{{ vs_msbuild_exe }}" --version 2>&1 | Select-String -Pattern '^\d+\.\d+'
    if (-not $ver) { exit 1 }
    $major = ($ver.Matches[0].Value -split '\.')[0]
    if ($major -ne {{ vs_version_major }}) {
      Write-Host "Expected MSBuild {{ vs_version_major }}.x, found $major"
      exit 1
    }
    Write-Host "MSBuild version OK: $($ver.Matches[0].Value)"
    exit 0
  when: msbuild_check.stat.exists
  register: msbuild_version_check
  changed_when: false

- name: "[{{ vs_install_label }}] Register MSBuild {{ vs_version_major }} dir in system PATH"
  ansible.windows.win_path:
    elements:
      - "{{ vs_install_path }}\\{{ vs_msbuild_paths[vs_version_major | string] }}"
    state: present
    scope: machine
  when: vs_register_msbuild_path

- name: "[{{ vs_install_label }}] Set MSBUILD_{{ vs_install_label | upper }}_PATH env var"
  ansible.windows.win_environment:
    name: "MSBUILD_{{ vs_install_label | upper }}_PATH"
    value: "{{ vs_msbuild_exe }}"
    state: present
    level: machine

- name: "[{{ vs_install_label }}] Verify .NET 8 SDK is available"
  ansible.windows.win_shell: |
    $sdks = & dotnet --list-sdks 2>&1
    if ($sdks -match '^8\.') {
      Write-Host "NET8 SDK found"
      exit 0
    }
    Write-Host "WARNING: .NET 8 SDK not found in dotnet CLI"
    Write-Host $sdks
    exit 0   # soft warn only — SDK may be in VS install dir
  register: dotnet_sdk_check
  changed_when: false
  ignore_errors: true

- name: "[{{ vs_install_label }}] Print MSBuild path summary"
  ansible.builtin.debug:
    msg:
      - "Install label   : {{ vs_install_label }}"
      - "MSBuild path    : {{ vs_msbuild_exe }}"
      - "Env var         : MSBUILD_{{ vs_install_label | upper }}_PATH"
      - "Version check   : {{ msbuild_version_check.stdout | default('skipped') | trim }}"
