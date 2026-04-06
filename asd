plugin: azure.azcollection.azure_rm
auth_source: cli
cloud_environment: AzureUSGovernment

include_vm_resource_groups:
  - '*'

conditional_groups:
  ghes_servers: "image.publisher == 'GitHub' and image.offer == 'GitHub-Enterprise'"
  backup_servers: "image.publisher == 'Canonical'"

hostvar_expressions:
  ansible_host: private_ipv4_addresses | first

keyed_groups:
  - prefix: publisher
    key: image.publisher | default('unknown')
  - prefix: offer
    key: image.offer | default('unknown')
