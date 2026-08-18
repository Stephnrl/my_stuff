name: Mirror Trivy DB to ACR

# Runs on a public-egress runner (no company data), copies the Trivy databases
# into ACR as OCI artifacts, and emits a freshness heartbeat.
#
# This is the hardest dependency in the whole gate. Self-hosted runners inside
# the Gov boundary generally cannot reach ghcr.io, so without this job every
# scan either fails outright or - far worse - runs against a stale DB and
# silently passes images it should have blocked.
#
# Trivy rebuilds the vulnerability DB roughly every 6 hours and the Java DB
# daily. Every 4 hours keeps us comfortably inside max_db_age_hours.

on:
  schedule:
    - cron: "0 */4 * * *"
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

concurrency:
  # Two mirror runs pushing the same tag would race on the ACR manifest.
  group: trivy-db-mirror
  cancel-in-progress: false

jobs:
  mirror:
    runs-on: ubuntu-latest
    environment: trivy-db-mirror
    steps:
      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ vars.GATE_CLIENT_ID }}
          tenant-id: ${{ vars.GATE_TENANT_ID }}
          subscription-id: ${{ vars.GATE_SUBSCRIPTION_ID }}
          environment: AzureUSGovernment

      - name: Install ORAS
        env:
          ORAS_VERSION: ${{ vars.ORAS_VERSION }}
          ORAS_SHA256: ${{ vars.ORAS_SHA256 }}
        run: |
          set -euo pipefail
          TARBALL="oras_${ORAS_VERSION}_linux_amd64.tar.gz"
          curl -fsSL --retry 3 -o "$TARBALL" \
            "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/${TARBALL}"
          echo "${ORAS_SHA256}  ${TARBALL}" | sha256sum -c -
          tar -xzf "$TARBALL" oras
          sudo install -m 0755 oras /usr/local/bin/oras
          oras version

      - name: Install Trivy
        env:
          TRIVY_VERSION: ${{ vars.GATE_TRIVY_VERSION }}
          TRIVY_SHA256: ${{ vars.GATE_TRIVY_SHA256 }}
        run: |
          set -euo pipefail
          TARBALL="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
          curl -fsSL --retry 3 -o "$TARBALL" \
            "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${TARBALL}"
          echo "${TRIVY_SHA256}  ${TARBALL}" | sha256sum -c -
          tar -xzf "$TARBALL" trivy
          sudo install -m 0755 trivy /usr/local/bin/trivy
          trivy --version

      - name: Log in to ACR
        env:
          ACR_NAME: ${{ vars.ACR_NAME }}
          ACR_LOGIN_SERVER: ${{ vars.ACR_LOGIN_SERVER }}
        run: |
          set -euo pipefail
          TOKEN=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken)
          echo "::add-mask::$TOKEN"
          oras login "$ACR_LOGIN_SERVER" \
            -u "00000000-0000-0000-0000-000000000000" \
            -p "$TOKEN"

      - name: Copy databases
        env:
          ACR_LOGIN_SERVER: ${{ vars.ACR_LOGIN_SERVER }}
        run: |
          set -euo pipefail
          oras cp -r ghcr.io/aquasecurity/trivy-db:2 \
            "${ACR_LOGIN_SERVER}/trivy/trivy-db:2"
          oras cp -r ghcr.io/aquasecurity/trivy-java-db:1 \
            "${ACR_LOGIN_SERVER}/trivy/trivy-java-db:1"

      - name: Verify the mirror is actually usable
        id: verify
        env:
          ACR_NAME: ${{ vars.ACR_NAME }}
          ACR_LOGIN_SERVER: ${{ vars.ACR_LOGIN_SERVER }}
        run: |
          set -euo pipefail
          # A successful push is not proof. Pull back through the mirror exactly
          # the way the gate will, then confirm the metadata parses and is fresh.
          TRIVY_PASSWORD=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken)
          echo "::add-mask::$TRIVY_PASSWORD"
          export TRIVY_PASSWORD
          export TRIVY_USERNAME="00000000-0000-0000-0000-000000000000"

          rm -rf ./dbcheck && mkdir -p ./dbcheck
          trivy image --cache-dir ./dbcheck --download-db-only \
            --db-repository "${ACR_LOGIN_SERVER}/trivy/trivy-db"

          UPDATED=$(jq -r '.UpdatedAt' ./dbcheck/db/metadata.json)
          echo "db_updated_at=$UPDATED" >> "$GITHUB_OUTPUT"

          AGE=$(( ( $(date -u +%s) - $(date -u -d "$UPDATED" +%s) ) / 3600 ))
          echo "Mirrored DB updated $UPDATED (${AGE}h old)"
          if (( AGE > 12 )); then
            echo "::error::Mirrored DB is ${AGE}h old immediately after a sync."
            echo "::error::Upstream publishing may be stalled. Investigate before"
            echo "::error::scans start silently passing against stale data."
            exit 1
          fi

      - name: Publish freshness heartbeat
        if: always()
        env:
          DCE_ENDPOINT: ${{ vars.GATE_DCE_ENDPOINT }}
          DCR_ID: ${{ vars.GATE_DCR_IMMUTABLE_ID }}
          JOB_STATUS: ${{ job.status }}
          DB_UPDATED: ${{ steps.verify.outputs.db_updated_at }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          set -euo pipefail
          # The Terraform alert watches for the ABSENCE of this heartbeat.
          # Alerting on job failure is not enough: a disabled schedule or a
          # deleted workflow produces no failure signal at all.
          jq -n \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg status "$JOB_STATUS" \
            --arg dbupdated "${DB_UPDATED:-}" \
            --arg url "$RUN_URL" \
            '[{
              TimeGenerated: $ts,
              ComponentId: "_infrastructure/trivy-db-mirror",
              GateResult: $status,
              VulnDbUpdatedAt: $dbupdated,
              RunUrl: $url
            }]' > heartbeat.json

          az rest --method post \
            --url "${DCE_ENDPOINT}/dataCollectionRules/${DCR_ID}/streams/Custom-SecurityGate_CL?api-version=2023-01-01" \
            --resource "https://monitor.azure.us" \
            --headers "Content-Type=application/json" \
            --body @heartbeat.json \
            || echo "::warning::Heartbeat emit failed; the silence alert may fire."
