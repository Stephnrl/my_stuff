---
- name: "[{{ vs_install_label }}] Check install sentinel"
  ansible.windows.win_stat:
    path: "{{ vs_install_sentinel }}"
  register: vs_sentinel_stat

- name: "[{{ vs_install_label }}] Run VS install tasks"
  ansible.builtin.include_tasks: install_vs.yml
  when: not vs_sentinel_stat.stat.exists

- name: "[{{ vs_install_label }}] Configure runner PATH and env"
  ansible.builtin.include_tasks: configure_runner.yml
