name: Trivy DB Canary

# REPLACES the old copy-based mirror workflow.
#
# With a JFrog (or any) pull-through remote proxying ghcr.io, nothing needs to
# be copied on a schedule - Artifactory fetches and caches on demand. The
# obvious move is to delete this workflow entirely. Do not.
#
# Deleting it silently removes two things:
#   1. The freshness heartbeat that the "db-mirror-silent" Azure alert watches
#      for. That alert fires on ABSENCE of signal; with no emitter it simply
#      never fires again and you lose stale-DB detection completely.
#   2. Any independent check that the pull-through path still works. A broken
#      remote repo, a revoked anonymous permission, or an expired upstream
#      credential inside Artifactory would otherwise surface as a confusing
#      failure in some team's build rather than as an infrastructure alert.
#
# So the job stops copying and becomes a canary: pull the DB the same way the
# gate does, assert it is fresh, emit the heartbeat.

on:
  schedule:
    - cron: "0 */4 * * *"
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

concurrency:
  group: trivy-db-canary
  cancel-in-progress: false

jobs:
  canary:
    # Runs wherever the gate runs. If your Gov-boundary runners reach JFrog but
    # ubuntu-latest does not (or vice versa), the canary must use the SAME
    # network path as the gate or it proves nothing.
    runs-on: ${{ vars.GATE_RUNNER_LABEL || 'self-hosted' }}
    steps:
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
          mkdir -p "$HOME/.local/bin"
          install -m 0755 trivy "$HOME/.local/bin/trivy"
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
          "$HOME/.local/bin/trivy" --version

      - name: Pull DB through the mirror
        id: pull
        env:
          DB_REPO: ${{ vars.GATE_DB_REPOSITORY }}
          JAVA_DB_REPO: ${{ vars.GATE_JAVA_DB_REPOSITORY }}
        run: |
          set -euo pipefail
          # No credentials, deliberately. This proves anonymous access still
          # works, which is exactly the assumption the gate depends on.
          export TRIVY_USERNAME="" TRIVY_PASSWORD=""

          rm -rf ./dbcheck && mkdir -p ./dbcheck
          START=$(date -u +%s)
          trivy image --cache-dir ./dbcheck --download-db-only \
            --db-repository "$DB_REPO" \
            --java-db-repository "$JAVA_DB_REPO"
          ELAPSED=$(( $(date -u +%s) - START ))

          UPDATED=$(jq -r '.UpdatedAt' ./dbcheck/db/metadata.json)
          NEXT=$(jq -r '.NextUpdate' ./dbcheck/db/metadata.json)
          {
            echo "db_updated_at=$UPDATED"
            echo "next_update=$NEXT"
            echo "elapsed=$ELAPSED"
          } >> "$GITHUB_OUTPUT"
          echo "Pulled in ${ELAPSED}s; DB updated $UPDATED, next $NEXT"

      - name: Assert freshness
        env:
          UPDATED: ${{ steps.pull.outputs.db_updated_at }}
          NEXT: ${{ steps.pull.outputs.next_update }}
          MAX_AGE: ${{ vars.GATE_MAX_DB_AGE_HOURS || '24' }}
        run: |
          set -euo pipefail
          AGE=$(( ( $(date -u +%s) - $(date -u -d "$UPDATED" +%s) ) / 3600 ))
          echo "Mirrored DB is ${AGE}h old (threshold ${MAX_AGE}h)"

          # A pull-through proxy can happily serve a cached manifest long after
          # NextUpdate has passed. Artifactory's Docker remote caches metadata
          # on its own schedule, which is invisible from here - this comparison
          # is the only thing that catches it.
          NOW_EPOCH=$(date -u +%s)
          NEXT_EPOCH=$(date -u -d "$NEXT" +%s 2>/dev/null || echo 0)
          if (( NEXT_EPOCH > 0 && NOW_EPOCH > NEXT_EPOCH )); then
            echo "::warning::DB is past its NextUpdate ($NEXT). The proxy may be"
            echo "::warning::serving a stale cached manifest. Check the remote repo's"
            echo "::warning::metadata cache TTL in Artifactory."
          fi

          if (( AGE > MAX_AGE )); then
            echo "::error::DB is ${AGE}h old, exceeding ${MAX_AGE}h."
            echo "::error::Either upstream publishing stalled or the proxy cache is stuck."
            exit 1
          fi

      - name: Publish freshness heartbeat
        if: always()
        env:
          DCE_ENDPOINT: ${{ vars.GATE_DCE_ENDPOINT }}
          DCR_ID: ${{ vars.GATE_DCR_IMMUTABLE_ID }}
          JOB_STATUS: ${{ job.status }}
          DB_UPDATED: ${{ steps.pull.outputs.db_updated_at }}
          ELAPSED: ${{ steps.pull.outputs.elapsed }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          set -euo pipefail
          # ComponentId is unchanged from the old mirror job, so the existing
          # "db-mirror-silent" alert keeps working with no Terraform edit.
          jq -n \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg status "$JOB_STATUS" \
            --arg dbupdated "${DB_UPDATED:-}" \
            --arg url "$RUN_URL" \
            --argjson elapsed "${ELAPSED:-0}" \
            '[{
              TimeGenerated: $ts,
              ComponentId: "_infrastructure/trivy-db-mirror",
              GateResult: $status,
              VulnDbUpdatedAt: $dbupdated,
              DurationSeconds: $elapsed,
              RunUrl: $url
            }]' > heartbeat.json

          az rest --method post \
            --url "${DCE_ENDPOINT}/dataCollectionRules/${DCR_ID}/streams/Custom-SecurityGate_CL?api-version=2023-01-01" \
            --resource "https://monitor.azure.us" \
            --headers "Content-Type=application/json" \
            --body @heartbeat.json \
            || echo "::warning::Heartbeat emit failed; the silence alert may fire."
