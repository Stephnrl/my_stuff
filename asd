# Example: composite action used INSIDE the caller's own job.
#
# The escape hatch for teams that need the scan in the same job as the build —
# for instance to scan before pushing. Same engine, same POA&M state, same
# policy; only the packaging differs.

name: Inline Gate

on: [workflow_dispatch]

permissions:
  contents: read
  id-token: write

jobs:
  build-and-gate:
    runs-on: self-hosted-gov
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ vars.GATE_CLIENT_ID }}
          tenant-id: ${{ vars.GATE_TENANT_ID }}
          subscription-id: ${{ vars.GATE_SUBSCRIPTION_ID }}
          environment: AzureUSGovernment

      - name: Build and push
        id: build
        run: |
          set -euo pipefail
          # ... build and push, however you like ...
          DIGEST=$(docker buildx imagetools inspect "${{ vars.ACR_LOGIN_SERVER }}/team/app:ci" \
            --format '{{ "{{" }}.Manifest.Digest{{ "}}" }}')
          echo "image_ref=${{ vars.ACR_LOGIN_SERVER }}/team/app@${DIGEST}" >> "$GITHUB_OUTPUT"

      - name: Security gate
        id: gate
        uses: myorg/security-gate@v1
        with:
          image_ref: ${{ steps.build.outputs.image_ref }}
          component_id: myorg/team/app
          policy_profile: observe
          registry: ${{ vars.ACR_LOGIN_SERVER }}
          state_store: az://${{ vars.GATE_STORAGE_ACCOUNT }}/poam
          trivy_version: ${{ vars.GATE_TRIVY_VERSION }}
          trivy_sha256: ${{ vars.GATE_TRIVY_SHA256 }}
          db_repository: ${{ vars.ACR_LOGIN_SERVER }}/trivy/trivy-db

      - name: Use the results
        run: |
          echo "Result: ${{ steps.gate.outputs.gate_result }}"
          echo "Initial scan: ${{ steps.gate.outputs.is_initial_scan }}"
          echo "POA&M: ${{ steps.gate.outputs.poam_uri }}"
