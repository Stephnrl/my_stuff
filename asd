# Example: ACR Task bootstrap build on a public pool, then the gate.
#
# This mirrors the flow where the bootstrap build carries no company data and
# runs on a public agent pool, then hands off to the gate inside the boundary.
#
# The only thing the gate needs from this job is the DIGEST. Note that
# component_id stays constant while image_tag carries a detailed release stamp
# — that split is what keeps POA&M history continuous across releases.

name: Build and Gate

on:
  push:
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      emergency_bypass:
        description: "Request emergency bypass (requires security approval)"
        type: boolean
        default: false
      bypass_reason:
        description: "Written justification — recorded permanently in the POA&M"
        type: string
        default: ""

permissions:
  contents: read
  id-token: write

jobs:
  build:
    # Public pool: no company data, no POA&M content, no state access.
    runs-on: ubuntu-latest
    outputs:
      image_ref: ${{ steps.acr.outputs.image_ref }}
      image_tag: ${{ steps.version.outputs.tag }}
    steps:
      - uses: actions/checkout@v4

      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ vars.BUILD_CLIENT_ID }}
          tenant-id: ${{ vars.GATE_TENANT_ID }}
          subscription-id: ${{ vars.GATE_SUBSCRIPTION_ID }}
          environment: AzureUSGovernment

      - name: Derive version stamp
        id: version
        run: |
          set -euo pipefail
          # Long semantic stamp. The gate does not care about this format —
          # any scheme works, because identity comes from the digest.
          TAG="${GITHUB_REF_NAME#v}-$(date -u +%Y%m%d%H%M%S)-${GITHUB_SHA::7}"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"

      - name: Build via ACR Task
        id: acr
        env:
          REGISTRY: ${{ vars.ACR_LOGIN_SERVER }}
          REPO: platform/api
          TAG: ${{ steps.version.outputs.tag }}
        run: |
          set -euo pipefail
          # Using a task yaml. Teams that prefer `az acr build`, docker build,
          # buildkit or kaniko all work the same way — they just need to end
          # at a digest.
          az acr run \
            --registry "${{ vars.ACR_NAME }}" \
            --file .acr/build-task.yaml \
            --set IMAGE="${REPO}:${TAG}" \
            .

          # Resolve the digest. This is the ONLY output the gate needs.
          DIGEST=$(az acr repository show \
            --name "${{ vars.ACR_NAME }}" \
            --image "${REPO}:${TAG}" \
            --query digest -o tsv)

          echo "image_ref=${REGISTRY}/${REPO}@${DIGEST}" >> "$GITHUB_OUTPUT"
          echo "Built ${REGISTRY}/${REPO}@${DIGEST}"

  security-gate:
    needs: build
    uses: myorg/security-gate/.github/workflows/gate.yml@v1
    with:
      image_ref: ${{ needs.build.outputs.image_ref }}
      # Stable across every release. NOT the version tag.
      component_id: myorg/platform/api
      image_tag: ${{ needs.build.outputs.image_tag }}
      policy_profile: fedramp-moderate
      registry: ${{ vars.ACR_LOGIN_SERVER }}
      runs_on: self-hosted-gov
      bypass_requested: ${{ inputs.emergency_bypass == true }}
      bypass_reason: ${{ inputs.bypass_reason }}
    secrets: inherit

  promote:
    needs: security-gate
    if: needs.security-gate.outputs.gate_result != 'fail'
    runs-on: self-hosted-gov
    steps:
      - name: Promote to release registry
        run: |
          echo "Gate: ${{ needs.security-gate.outputs.gate_result }}"
          echo "New findings: ${{ needs.security-gate.outputs.new_count }}"
          echo "Closed this run: ${{ needs.security-gate.outputs.closed_count }}"
          echo "Promoting ${{ needs.security-gate.outputs.image_digest }}"
