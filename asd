ignore_dirs:
  - examples
  - .terraform
  - .git

profiles:
  security:
    description: Resources deployed into the central security account
  member:
    description: Resources deployed into each member account

file_roles:
  - file: security.tf
    deployment_mode: security
    account_scope: security account
    tags:
      - central
      - security

  - file: member.tf
    deployment_mode: member
    account_scope: member account
    tags:
      - member

directory_roles:
  - directory: aws_config
    logical_group: AWS Config
    tags:
      - compliance

  - directory: cw_oam_sink
    logical_group: OAM Sink
    account_scope: security account
    deployment_mode: security
    tags:
      - observability
      - central

  - directory: cw_oam_link
    logical_group: OAM Link
    account_scope: member account
    deployment_mode: member
    tags:
      - observability
      - member

logical_components:
  - name: AWS Config - Security Account
    type: compliance
    directories:
      - aws_config
    files:
      - security.tf
    account_scope: security account
    deployment_modes:
      - security
    description: Central AWS Config resources for the security account

  - name: AWS Config - Member Account
    type: compliance
    directories:
      - aws_config
    files:
      - member.tf
    account_scope: member account
    deployment_modes:
      - member
    description: AWS Config resources deployed in member accounts

  - name: OAM Sink
    type: observability
    directories:
      - cw_oam_sink
    account_scope: security account
    deployment_modes:
      - security
    description: CloudWatch OAM sink in the central security account

  - name: OAM Link
    type: observability
    directories:
      - cw_oam_link
    account_scope: member account
    deployment_modes:
      - member
    connects_to:
      - OAM Sink
    description: CloudWatch OAM link in each member account

flows:
  - from: OAM Link
    to: OAM Sink
    label: metrics / logs / traces

  - from: AWS Config - Member Account
    to: AWS Config - Security Account
    label: config aggregation / compliance visibility
