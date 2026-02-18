name: machine-file-copy
description: Copies files to machine

inputs:
  azure-credentials:
    description: Azure credentials JSON
    required: true

runs:
  using: composite
  steps:
    - uses: azure/login@v2
      with:
        creds: ${{ inputs.azure-credentials }}
        environment: 'AzureUSGovernment'
        enable-AzPSSession: true

    - shell: pwsh
      run: |
        # your file copy logic here, Az context is now available
