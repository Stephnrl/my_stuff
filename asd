name: 'Code Signing with Azure Key Vault'
description: 'Signs binaries and ClickOnce/VSTO manifests using dotnet/sign CLI with Azure Key Vault (supports Gov Cloud + OIDC)'
author: 'YourOrg'

branding:
  icon: 'lock'
  color: 'blue'

inputs:
  azure-tenant-id:
    description: 'Azure AD Tenant ID'
    required: true
  azure-client-id:
    description: 'Azure AD Application (Client) ID for the SPN'
    required: true
  azure-subscription-id:
    description: 'Azure Subscription ID'
    required: true
  azure-environment:
    description: 'Azure environment (AzureCloud or AzureUSGovernment)'
    required: false
    default: 'AzureUSGovernment'
  key-vault-url:
    description: 'Azure Key Vault URL (e.g. https://myvault.vault.usgovcloudapi.net)'
    required: true
  key-vault-certificate:
    description: 'Certificate name in Azure Key Vault'
    required: true
  base-directory:
    description: 'Base directory containing files to sign'
    required: true
  file-list:
    description: 'Path to a file containing glob patterns of files to sign (one per line). If empty, all supported files in base-directory are signed.'
    required: false
    default: ''
  timestamp-url:
    description: 'RFC 3161 timestamp server URL. Set to empty string to skip timestamping.'
    required: false
    default: 'http://timestamp.digicert.com'
  sign-tool-version:
    description: 'Version of the dotnet sign CLI tool to install (use "latest" for latest prerelease)'
    required: false
    default: 'latest'
  verbosity:
    description: 'Logging verbosity (quiet, minimal, normal, detailed, diagnostic)'
    required: false
    default: 'minimal'
  dotnet-version:
    description: '.NET SDK version required by sign CLI'
    required: false
    default: '8.0.x'

outputs:
  signed-files-count:
    description: 'Number of files that were signed'
    value: ${{ steps.sign.outputs.signed-files-count }}

runs:
  using: 'composite'
  steps:
    - name: Validate runner OS
      shell: pwsh
      run: |
        if ($env:RUNNER_OS -ne 'Windows') {
          Write-Error "::error::This action requires a Windows runner (runs-on: windows-latest or self-hosted Windows). Current OS: $env:RUNNER_OS"
          exit 1
        }

    - name: Setup .NET SDK
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: ${{ inputs.dotnet-version }}

    - name: Run Code Signing
      id: sign
      shell: pwsh
      env:
        INPUT_AZURE_TENANT_ID: ${{ inputs.azure-tenant-id }}
        INPUT_AZURE_CLIENT_ID: ${{ inputs.azure-client-id }}
        INPUT_AZURE_SUBSCRIPTION_ID: ${{ inputs.azure-subscription-id }}
        INPUT_AZURE_ENVIRONMENT: ${{ inputs.azure-environment }}
        INPUT_KEY_VAULT_URL: ${{ inputs.key-vault-url }}
        INPUT_KEY_VAULT_CERTIFICATE: ${{ inputs.key-vault-certificate }}
        INPUT_BASE_DIRECTORY: ${{ inputs.base-directory }}
        INPUT_FILE_LIST: ${{ inputs.file-list }}
        INPUT_TIMESTAMP_URL: ${{ inputs.timestamp-url }}
        INPUT_SIGN_TOOL_VERSION: ${{ inputs.sign-tool-version }}
        INPUT_VERBOSITY: ${{ inputs.verbosity }}
      run: |
        $actionRoot = "${{ github.action_path }}"
        & "$actionRoot/src/entrypoint.ps1"
