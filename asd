inputs:
  - id: playbook
    name: Playbook to run
    type: select
    options:
      - playbooks/configure/rhel/main.yml
      - playbooks/configure/ubuntu/main.yml
      - playbooks/patch/rhel/security.yml
      - playbooks/deploy/app/main.yml
      # add every entry-point playbook you want selectable here

  - id: env
    name: Environment
    type: select
    options:
      - prod
      - staging
      - dev

  - id: stack_name
    name: Stack name
    type: short_text
    validations:
      required: true
      pattern: "^[a-z0-9-]+$"

options:
  # create a tracked run immediately after the stack is created
  trigger_run: false

stack:
  name: ${{ inputs.stack_name }}-${{ inputs.env }}
  space: root
  description: 'Ansible (Azure Gov) running ${{ inputs.playbook }} in ${{ inputs.env }}.'
  labels:
    - Environment/${{ inputs.env }}
    - Vendor/Ansible
    - Cloud/AzureUSGov
    - Owner/${{ context.user.login }}

  # Use a runner image that includes azure.azcollection + its pip deps,
  # or install them via requirements.yml at runtime (see note below).
  runner_image: my-registry.example.com/spacelift-ansible-azure:latest
  # worker_pool: 01GQ...   # strongly recommended for gov: a private worker inside your gov subscription

  vcs:
    branch: main
    repository: my-ansible-repo
    namespace: my-org
    provider: GITHUB
    # project_root: ansible

  vendor:
    ansible:
      playbook: ${{ inputs.playbook }}

  environment:
    variables:
      - name: AZURE_CLOUD_ENVIRONMENT
        value: AzureUSGovernment          # <-- the gov cloud switch
        description: Targets Azure US Government ARM endpoints
      - name: ANSIBLE_PRIVATE_KEY_FILE
        value: /mnt/workspace/id_rsa
        description: SSH key path for connecting to hosts

  attachments:
    contexts:
      # Put the service principal creds in a shared Context, attach it here.
      # Keeps secrets out of the blueprint YAML and reusable across stacks.
      - id: azure-gov-sp-credentials
