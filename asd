name: smoke-test-aap-connectivity

# Run this FIRST before the real launch test. Validates:
#   - The runner can reach AAP
#   - The token is valid
#   - The target job template exists and is launchable
# No job is actually launched.

on:
  workflow_dispatch:
    inputs:
      job_template:
        description: AAP job template ID or name to validate
        required: true
        type: string

permissions:
  contents: read

jobs:
  smoke:
    runs-on: self-hosted
    steps:
      - name: Checkout shared actions
        uses: actions/checkout@v4
        with:
          repository: your-org/gha-actions
          ref: v1.4.0
          path: .gha-actions
          token: ${{ secrets.INTERNAL_REPO_PAT }}

      - name: Validate AAP connectivity and JT
        shell: pwsh
        env:
          AAP_URL:   ${{ secrets.AAP_URL }}
          AAP_TOKEN: ${{ secrets.AAP_OAUTH_TOKEN }}
          JT:        ${{ inputs.job_template }}
        run: |
          $ErrorActionPreference = 'Stop'
          Import-Module ./.gha-actions/launch-aap-job-pwsh/AAP/AAP.psd1 -Force

          Write-Host "Connecting to $env:AAP_URL ..."
          Connect-AAPController -BaseUrl $env:AAP_URL -Token $env:AAP_TOKEN
          Write-Host "✓ Connected"

          Write-Host "Resolving job template '$env:JT' ..."
          $jtId = Resolve-AAPJobTemplate -Identifier $env:JT
          Write-Host "✓ Job template resolved to ID $jtId"

          Write-Host ""
          Write-Host "All checks passed. Safe to run the real launch workflow."
