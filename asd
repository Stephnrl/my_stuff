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
  description: 'Ansible stack running ${{ inputs.playbook }} against ${{ inputs.env }}.'
  labels:
    - Environment/${{ inputs.env }}
    - Vendor/Ansible
    - Owner/${{ context.user.login }}

  runner_image: public.ecr.aws/spacelift/runner-ansible-aws:latest
  # worker_pool: 01GQ...   # uncomment + set if you use a private worker pool

  vcs:
    branch: main
    repository: my-ansible-repo
    namespace: my-org        # GitHub org / GitLab group / Bitbucket project
    provider: GITHUB
    # project_root: ansible  # set if your playbooks live in a subfolder of the repo

  vendor:
    ansible:
      playbook: ${{ inputs.playbook }}

  environment:
    variables:
      - name: ANSIBLE_PRIVATE_KEY_FILE
        value: /mnt/workspace/id_rsa
        description: SSH key path for connecting to hosts
      - name: SPACELIFT_ANSIBLE_CLI_ARGS
        value: -e target_env=${{ inputs.env }}
        description: Passes the environment through as an extra-var

  attachments:
    contexts:
      - id: my-ansible-context   # holds shared env vars / mounted SSH key, etc.
    clouds:
      aws:
        id: 01GQ29K8SYXKZVHPZ4HG00BK2E   # your AWS integration ID
        read: true
        write: true
