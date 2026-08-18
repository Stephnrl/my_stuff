name: Container Security Gate

# Teams call this. The contract is deliberately small: a digest and a stable
# component_id. How the image got built is none of the gate's business, which is
# what lets ACR Tasks, docker build, buildkit and kaniko all share one gate.

on:
  workflow_call:
    inputs:
      image_ref:
        description: "Digest-pinned reference: <registry>/<repo>@sha256:..."
        required: true
        type: string
      component_id:
        description: "Stable POA&M identity. Must NOT change between releases."
        required: true
        type: string
      image_tag:
        description: "Display tag. Metadata only."
        required: false
        type: string
        default: ""
      policy_profile:
        description: "fedramp-moderate | standard | observe"
        required: false
        type: string
        default: "standard"
      registry:
        description: "ACR login server, e.g. myacr.azurecr.us"
        required: true
        type: string
      runs_on:
        description: "Runner label. Must be inside the Gov boundary - POA&M content is sensitive."
        required: false
        type: string
        default: "self-hosted"
      bypass_requested:
        description: "Requires approval in the security-gate-bypass environment."
        required: false
        type: boolean
        default: false
      bypass_reason:
        description: "Written justification. Recorded permanently in the POA&M."
        required: false
        type: string
        default: ""
      upload_artifacts:
        required: false
        type: boolean
        default: false
    secrets:
      # Declared explicitly rather than relying on `secrets: inherit`. Callers
      # can still use inherit, but naming them documents the trust surface.
      EXCEPTIONS_READ_TOKEN:
        description: "Read access to the central exception repository."
        required: false
      SECURITY_TEAMS_WEBHOOK:
        description: "Teams/Slack webhook for bypass and regression alerts."
        required: false
    outputs:
      gate_result:
        description: "pass | fail | pass_with_bypass"
        value: ${{ jobs.scan.outputs.gate_result }}
      image_digest:
        description: "Digest that was scanned"
        value: ${{ jobs.scan.outputs.image_digest }}
      new_count:
        description: "Findings first seen in this scan"
        value: ${{ jobs.scan.outputs.new_count }}
      closed_count:
        description: "Findings remediated since the previous scan"
        value: ${{ jobs.scan.outputs.closed_count }}
      reopened_count:
        description: "Previously closed findings that returned"
        value: ${{ jobs.scan.outputs.reopened_count }}
      poam_uri:
        description: "Blob URI of the generated POA&M"
        value: ${{ jobs.scan.outputs.poam_uri }}

permissions:
  contents: read
  id-token: write

jobs:
  # Bypass is a separate, environment-gated job. The environment carries the
  # required reviewers, so approver identity and timestamp are recorded by
  # GitHub itself rather than trusted from a workflow input.
  approve-bypass:
    if: inputs.bypass_requested
    runs-on: ubuntu-latest
    environment: security-gate-bypass
    outputs:
      approved_by: ${{ steps.record.outputs.approved_by }}
    steps:
      - name: Record the approval
        id: record
        env:
          BYPASS_REASON: ${{ inputs.bypass_reason }}
          COMPONENT_ID: ${{ inputs.component_id }}
          IMAGE_REF: ${{ inputs.image_ref }}
          REQUESTED_BY: ${{ github.actor }}
        run: |
          set -euo pipefail
          if [[ -z "${BYPASS_REASON// /}" ]]; then
            echo "::error::A bypass requires a written justification."
            echo "::error::It is recorded permanently in the POA&M."
            exit 1
          fi
          echo "approved_by=${REQUESTED_BY}" >> "$GITHUB_OUTPUT"

          {
            echo "## Security gate bypass approved"
            echo ""
            echo "| Field | Value |"
            echo "|---|---|"
            echo "| Component | \`${COMPONENT_ID}\` |"
            echo "| Image | \`${IMAGE_REF}\` |"
            echo "| Requested by | ${REQUESTED_BY} |"
            echo "| Justification | ${BYPASS_REASON} |"
            echo ""
            echo "Recorded in the POA&M; the security team has been alerted."
          } >> "$GITHUB_STEP_SUMMARY"

  scan:
    needs: [approve-bypass]
    # Runs whether or not a bypass was requested. When bypass_requested is
    # false the approval job is skipped, and a skipped dependency would
    # normally skip this job too - hence the explicit result check.
    if: >-
      always() && !cancelled() &&
      (needs.approve-bypass.result == 'success' || needs.approve-bypass.result == 'skipped')
    runs-on: ${{ inputs.runs_on }}
    outputs:
      gate_result: ${{ steps.gate.outputs.gate_result }}
      image_digest: ${{ steps.gate.outputs.image_digest }}
      new_count: ${{ steps.gate.outputs.new_count }}
      closed_count: ${{ steps.gate.outputs.closed_count }}
      reopened_count: ${{ steps.gate.outputs.reopened_count }}
      overdue_count: ${{ steps.gate.outputs.overdue_count }}
      critical_open: ${{ steps.gate.outputs.critical_open }}
      poam_uri: ${{ steps.gate.outputs.poam_uri }}
    steps:
      - name: Azure login (OIDC federated credential)
        uses: azure/login@v2
        with:
          client-id: ${{ vars.GATE_CLIENT_ID }}
          tenant-id: ${{ vars.GATE_TENANT_ID }}
          subscription-id: ${{ vars.GATE_SUBSCRIPTION_ID }}
          environment: AzureUSGovernment

      - name: Run security gate
        id: gate
        uses: myorg/security-gate@v1
        with:
          image_ref: ${{ inputs.image_ref }}
          component_id: ${{ inputs.component_id }}
          image_tag: ${{ inputs.image_tag }}
          policy_profile: ${{ inputs.policy_profile }}
          registry: ${{ inputs.registry }}
          state_store: az://${{ vars.GATE_STORAGE_ACCOUNT }}/poam
          azure_environment: usgovernment
          trivy_version: ${{ vars.GATE_TRIVY_VERSION }}
          trivy_sha256: ${{ vars.GATE_TRIVY_SHA256 }}
          db_repository: ${{ inputs.registry }}/trivy/trivy-db
          java_db_repository: ${{ inputs.registry }}/trivy/trivy-java-db
          exceptions_repo: ${{ vars.GATE_EXCEPTIONS_REPO }}
          exceptions_token: ${{ secrets.EXCEPTIONS_READ_TOKEN }}
          dce_endpoint: ${{ vars.GATE_DCE_ENDPOINT }}
          dcr_immutable_id: ${{ vars.GATE_DCR_IMMUTABLE_ID }}
          bypass: ${{ inputs.bypass_requested }}
          bypass_reason: ${{ inputs.bypass_reason }}
          bypass_actor: ${{ needs.approve-bypass.outputs.approved_by }}
          upload_artifacts: ${{ inputs.upload_artifacts }}

      - name: Notify on bypass
        if: always() && steps.gate.outputs.gate_result == 'pass_with_bypass'
        env:
          WEBHOOK: ${{ secrets.SECURITY_TEAMS_WEBHOOK }}
          COMPONENT_ID: ${{ inputs.component_id }}
          IMAGE_REF: ${{ inputs.image_ref }}
          APPROVED_BY: ${{ needs.approve-bypass.outputs.approved_by }}
          BYPASS_REASON: ${{ inputs.bypass_reason }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          set -euo pipefail
          if [[ -z "$WEBHOOK" ]]; then
            echo "::warning::No SECURITY_TEAMS_WEBHOOK configured; bypass alert not sent."
            exit 0
          fi

          # Built with jq --arg so a justification containing quotes, newlines
          # or backslashes cannot corrupt the payload or inject fields.
          jq -n \
            --arg component "$COMPONENT_ID" \
            --arg image "$IMAGE_REF" \
            --arg approver "$APPROVED_BY" \
            --arg reason "$BYPASS_REASON" \
            --arg url "$RUN_URL" \
            '{text: ("Security gate BYPASSED\n\nComponent: " + $component
                     + "\nImage: " + $image
                     + "\nApproved by: " + $approver
                     + "\nReason: " + $reason
                     + "\nRun: " + $url)}' \
            > "$RUNNER_TEMP/bypass-alert.json"

          curl -fsS -X POST "$WEBHOOK" \
            -H 'Content-Type: application/json' \
            --data @"$RUNNER_TEMP/bypass-alert.json" \
            || echo "::warning::Bypass notification failed to send"

      - name: Flag regressions
        if: always() && steps.gate.outputs.reopened_count != '' && steps.gate.outputs.reopened_count != '0'
        env:
          REOPENED: ${{ steps.gate.outputs.reopened_count }}
        run: |
          echo "::warning::${REOPENED} previously-closed finding(s) have returned."
          echo "::warning::Usually a base-image rollback or a reverted dependency bump."
