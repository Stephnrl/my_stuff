# Example: plain docker build + push, no ACR Tasks, simple tagging.
#
# Contrast with caller-acr-task.yml: completely different build tooling and a
# much simpler version scheme, but the gate call is nearly identical. That is
# the point of the contract.

name: Build and Gate (docker)

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image_ref: ${{ steps.push.outputs.image_ref }}
    steps:
      - uses: actions/checkout@v4

      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ vars.BUILD_CLIENT_ID }}
          tenant-id: ${{ vars.GATE_TENANT_ID }}
          subscription-id: ${{ vars.GATE_SUBSCRIPTION_ID }}
          environment: AzureUSGovernment

      - uses: docker/setup-buildx-action@v3

      - name: Log in to ACR
        run: |
          set -euo pipefail
          TOKEN=$(az acr login --name "${{ vars.ACR_NAME }}" --expose-token --output tsv --query accessToken)
          echo "::add-mask::$TOKEN"
          echo "$TOKEN" | docker login "${{ vars.ACR_LOGIN_SERVER }}" \
            -u "00000000-0000-0000-0000-000000000000" --password-stdin

      - name: Build and push
        id: push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ vars.ACR_LOGIN_SERVER }}/team/worker:latest

      - name: Emit digest-pinned reference
        id: ref
        run: |
          echo "image_ref=${{ vars.ACR_LOGIN_SERVER }}/team/worker@${{ steps.push.outputs.digest }}" >> "$GITHUB_OUTPUT"

  security-gate:
    needs: build
    uses: myorg/security-gate/.github/workflows/gate.yml@v1
    with:
      # Team uses a mutable :latest tag; the gate still gets an immutable digest,
      # and POA&M continuity is anchored on component_id regardless.
      image_ref: ${{ needs.build.outputs.image_ref }}
      component_id: myorg/team/worker
      image_tag: latest
      policy_profile: standard
      registry: ${{ vars.ACR_LOGIN_SERVER }}
      runs_on: self-hosted-gov
    secrets: inherit
