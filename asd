name: deploy-rhel9-vm

on:
  workflow_dispatch:
    inputs:
      environment:
        description: Target environment
        required: true
        default: prod
        type: choice
        options: [dev, test, prod]

permissions:
  id-token: write   # OIDC federation to Azure
  contents: read

jobs:
  terraform:
    runs-on: self-hosted   # runner must reach Azure Gov + AAP
    environment: ${{ inputs.environment }}
    outputs:
      vm_name: ${{ steps.tfout.outputs.vm_name }}
      vm_private_ip: ${{ steps.tfout.outputs.vm_private_ip }}
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          environment: AzureUSGovernment

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.8

      - name: terraform init
        working-directory: examples/rhel9-cmmc
        run: terraform init

      - name: terraform apply
        working-directory: examples/rhel9-cmmc
        env:
          TF_VAR_aap_admin_public_key: ${{ secrets.AAP_ADMIN_PUBLIC_KEY }}
        run: terraform apply -auto-approve

      - name: capture outputs
        id: tfout
        working-directory: examples/rhel9-cmmc
        run: |
          echo "vm_name=$(terraform output -raw vm_name)" >> "$GITHUB_OUTPUT"
          echo "vm_private_ip=$(terraform output -raw vm_private_ip)" >> "$GITHUB_OUTPUT"

  configure:
    needs: terraform
    runs-on: self-hosted
    environment: ${{ inputs.environment }}
    steps:
      - name: Launch AAP 2.5 job template
        env:
          AAP_URL:         ${{ secrets.AAP_URL }}            # e.g. https://aap.example.gov
          AAP_TOKEN:       ${{ secrets.AAP_OAUTH_TOKEN }}    # OAuth2 token, scoped to a service user
          JOB_TEMPLATE_ID: ${{ vars.AAP_JT_RHEL9_CONFIGURE }} # numeric JT id
          VM_NAME:         ${{ needs.terraform.outputs.vm_name }}
          VM_IP:           ${{ needs.terraform.outputs.vm_private_ip }}
        run: |
          set -euo pipefail

          # 1. Launch the job template with extra_vars. 'limit' scopes the run to just this host
          #    so the JT can be a one-template-fits-all playbook against a dynamic Azure inventory.
          launch_resp=$(curl -sSf -X POST \
            -H "Authorization: Bearer ${AAP_TOKEN}" \
            -H "Content-Type: application/json" \
            --data @- \
            "${AAP_URL}/api/controller/v2/job_templates/${JOB_TEMPLATE_ID}/launch/" <<EOF
          {
            "limit": "${VM_NAME}",
            "extra_vars": {
              "target_host":     "${VM_NAME}",
              "target_ip":       "${VM_IP}",
              "cmmc_level":      "2",
              "data_classification": "cui"
            }
          }
          EOF
          )

          job_id=$(echo "${launch_resp}" | jq -r '.id')
          echo "Launched AAP job ${job_id}"
          echo "AAP job URL: ${AAP_URL}/#/jobs/playbook/${job_id}/output"

          # 2. Poll until the job is terminal.
          while : ; do
            status=$(curl -sSf \
              -H "Authorization: Bearer ${AAP_TOKEN}" \
              "${AAP_URL}/api/controller/v2/jobs/${job_id}/" | jq -r '.status')
            case "${status}" in
              successful)
                echo "AAP job ${job_id} succeeded."
                exit 0 ;;
              failed|error|canceled)
                echo "AAP job ${job_id} ended with status: ${status}" >&2
                # Pull last 200 lines of stdout for triage in the Action log
                curl -sSf \
                  -H "Authorization: Bearer ${AAP_TOKEN}" \
                  "${AAP_URL}/api/controller/v2/jobs/${job_id}/stdout/?format=txt&content_encoding=raw" \
                  | tail -200 >&2
                exit 1 ;;
              *)
                echo "status=${status} — sleeping 15s"
                sleep 15 ;;
            esac
          done
