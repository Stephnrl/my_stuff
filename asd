- name: "[{{ vs_install_label }}] Install VS Build Tools"
  ansible.windows.win_shell: |
    $arguments = @(
        "--quiet",
        "--norestart",
        "--wait",
        "--nocache",
        "--installPath", '"{{ vs_install_path }}"',   # <-- explicit quoting
        "--config",     '"C:\Windows\Temp\vs_response_{{ vs_install_label }}.json"',
        "--log",        '"{{ vs_install_log }}"'
    )
    $proc = Start-Process `
        -FilePath "{{ vs_installer_dest }}" `
        -ArgumentList $arguments `
        -Wait `
        -PassThru `
        -NoNewWindow
    exit $proc.ExitCode
  register: vs_install_result
  failed_when: vs_install_result.rc not in [0, 3010]
  async: "{{ vs_install_timeout }}"
  poll: 30
