---
- name: "[{{ vs_install_label }}] Ensure install directories exist"
  ansible.windows.win_file:
    path: "{{ item }}"
    state: directory
  loop:
    - "{{ vs_install_path }}"
    - "C:\\BuildTools"

- name: "[{{ vs_install_label }}] Write VS response file"
  ansible.windows.win_template:
    src: vs_response.json.j2
    dest: "C:\\Windows\\Temp\\vs_response_{{ vs_install_label }}.json"

- name: "[{{ vs_install_label }}] Download VS Build Tools installer"
  ansible.windows.win_get_url:
    url: "{{ vs_installer_url }}"
    dest: "{{ vs_installer_dest }}"
    # Force re-download only if installer is missing
    force: false
  register: vs_download

- name: "[{{ vs_install_label }}] Install VS Build Tools (this takes a while)"
  ansible.windows.win_shell: |
    $proc = Start-Process -FilePath "{{ vs_installer_dest }}" `
      -ArgumentList @(
        '--quiet',
        '--norestart',
        '--wait',
        '--nocache',
        '--installPath', '{{ vs_install_path }}',
        '--config', 'C:\Windows\Temp\vs_response_{{ vs_install_label }}.json',
        '--log', '{{ vs_install_log }}'
      ) `
      -Wait `
      -PassThru
    exit $proc.ExitCode
  register: vs_install_result
  # Exit code 0 = success, 3010 = success + reboot needed
  failed_when: vs_install_result.rc not in [0, 3010]
  async: "{{ vs_install_timeout }}"
  poll: 30

- name: "[{{ vs_install_label }}] Validate MSBuild.exe exists at expected path"
  ansible.windows.win_stat:
    path: "{{ vs_msbuild_exe }}"
  register: msbuild_stat
  failed_when: not msbuild_stat.stat.exists

- name: "[{{ vs_install_label }}] Write install sentinel"
  ansible.windows.win_copy:
    content: |
      installed={{ vs_install_label }}
      msbuild={{ vs_msbuild_exe }}
      date={{ ansible_date_time.iso8601 }}
    dest: "{{ vs_install_sentinel }}"

- name: "[{{ vs_install_label }}] Reboot if installer requested it"
  ansible.windows.win_reboot:
    reboot_timeout: 600
  when: vs_install_result.rc == 3010
