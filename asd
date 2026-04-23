plugin: azure.azcollection.azure_rm
include_vm_resource_groups:
  - rg-app-prod
keyed_groups:
  - prefix: env
    key: tags.environment
  - prefix: cmmc
    key: tags.cmmc_level
  - prefix: role
    key: tags.role
hostnames:
  - name      # uses VM name as the Ansible hostname
compose:
  ansible_host: private_ipv4_addresses[0]
