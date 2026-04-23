name: test-aap-launch

# Manual trigger so you can iterate without Terraform in the loop.
# Inputs default to the VM you just deployed — override at run time as needed.
on:
  workflow_dispatch:
    inputs:
      vm_name:
        description: VM name (Ansible inventory hostname)
        required: true
        type: string
      vm_ip:
        description: VM private IP
        required: true
        type: string
      job_template:
        description: AAP job template ID or name
        required: true
        type: string
      timeout_seconds:
        description: How long to wait for the job before timing out
        required: false
        default: "1800"
        type: string
      dry_run:
        description: If true, AAP will run with --check (no changes made)
        required: false
        default: false
        type: boolean

permissions:
  contents: read

jobs:
  configure:
    runs-on: self-hosted
    steps:
      - name: Checkout shared actions
        uses: actions/checkout@v4
        with:
          repository: your-org/gha-actions
          ref: v1.4.0                              # pin to a tag, never @main
          path: .gha-actions
          token: ${{ secrets.INTERNAL_REPO_PAT }}

      - name: Launch AAP job
        id: aap
        uses: ./.gha-actions/launch-aap-job-pwsh
        with:
          aap-url:      ${{ secrets.AAP_URL }}
          aap-token:    ${{ secrets.AAP_OAUTH_TOKEN }}
          job-template: ${{ inputs.job_template }}
          limit:        ${{ inputs.vm_name }}
          timeout-seconds: ${{ inputs.timeout_seconds }}
          extra-vars: |
            {
              "target_host":         "${{ inputs.vm_name }}",
              "target_ip":           "${{ inputs.vm_ip }}",
              "cmmc_level":          "2",
              "data_classification": "cui",
              "ansible_check_mode":  ${{ inputs.dry_run }}
            }

      - name: Show outputs
        if: always()
        run: |
          echo "Job ID:  ${{ steps.aap.outputs.job-id }}"
          echo "Job URL: ${{ steps.aap.outputs.job-url }}"
          echo "Status:  ${{ steps.aap.outputs.status }}"
