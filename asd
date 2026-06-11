1. Reusable security gate — replace the registry inputs/secrets:
yamlon:
  workflow_call:
    inputs:
      acr-name:                 # replaces `registry`; empty skips login
        required: false
        type: string
        default: ''
    secrets:                    # replaces registry-username/password
      azure-client-id:
        required: false
      azure-tenant-id:
        required: false
      azure-subscription-id:
        required: false
2. Replace the login steps (and add id-token: write to the job's permissions block alongside the existing contents: write):
yaml      - name: Azure login (OIDC)
        if: inputs.acr-name != ''
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.azure-client-id }}
          tenant-id: ${{ secrets.azure-tenant-id }}
          subscription-id: ${{ secrets.azure-subscription-id }}

      - name: ACR login (token exchange, no stored credentials)
        if: inputs.acr-name != ''
        run: az acr login --name "${{ inputs.acr-name }}"
az acr login exchanges the AAD token for an ACR refresh token and writes it into ~/.docker/config.json, which trivy-action picks up automatically — so the scan and SBOM steps need no changes. The token is valid ~3 hours, plenty for a gate job.
3. Caller side — the caller must grant the permissions the reusable workflow needs (called workflows can't exceed the caller's grant):
yaml  security-gate:
    needs: zone-a-bootstrap
    permissions:
      id-token: write          # OIDC federation
      contents: write          # POA&M state branch
    uses: your-org/ci-templates/.github/workflows/reusable-security-gate.yml@v1
    with:
      image-ref: ${{ needs.zone-a-bootstrap.outputs.image-ref }}
      system-name: github-runner-image
      acr-name: myacr
    secrets: inherit           # or pass azure-* explicitly
4. Daemon-less variant, useful if a job has no docker daemon or you'd rather hand credentials straight to Trivy instead of touching docker config:
yaml      - name: Get ACR access token
        id: acr
        run: |
          TOKEN=$(az acr login --name myacr --expose-token \
            --output tsv --query accessToken)
          echo "::add-mask::$TOKEN"
          echo "token=$TOKEN" >> "$GITHUB_OUTPUT"

      - uses: aquasecurity/trivy-action@0.28.0
        env:
          TRIVY_USERNAME: 00000000-0000-0000-0000-000000000000
          TRIVY_PASSWORD: ${{ steps.acr.outputs.token }}
        with:
          image-ref: ${{ inputs.image-ref }}
          format: json
          output: trivy-results.json
