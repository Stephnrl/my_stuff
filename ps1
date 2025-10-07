name: Test Key Vault Script

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to test (prod, dev, test, uat)'
        required: true
        type: choice
        options:
          - dev
          - development
          - test
          - uat
          - prod
          - production
      admin-security-id:
        description: 'Admin Security ID to retrieve'
        required: true
        type: string
      admin-security-domain:
        description: 'Admin Security Domain'
        required: false
        type: string
        default: 'snc'

jobs:
  test-script:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Display Parameters
        run: |
          echo "Environment: ${{ inputs.environment }}"
          echo "Security ID: ${{ inputs.admin-security-id }}"
          echo "Domain: ${{ inputs.admin-security-domain }}"
      
      - name: Test Key Vault Script
        shell: pwsh
        env:
          ENV_NAME: ${{ inputs.environment }}
          SECURITY_ID: ${{ inputs.admin-security-id }}
          SECURITY_DOMAIN: ${{ inputs.admin-security-domain }}
        run: |
          Write-Host "Testing Key Vault credential retrieval..."
          Write-Host "Environment: $env:ENV_NAME"
          Write-Host "Security ID: $env:SECURITY_ID"
          Write-Host "Domain: $env:SECURITY_DOMAIN"
          
          # Run the main script with proper parameter passing
          & "${{ github.workspace }}/scripts/Main.ps1" `
            -Environment "$env:ENV_NAME" `
            -AdminSecurityId "$env:SECURITY_ID" `
            -AdminSecurityDomain "$env:SECURITY_DOMAIN"
