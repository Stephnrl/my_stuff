name: "Dispatch and Wait"
description: >
  Send a repository_dispatch to a downstream repo, then poll until the
  triggered workflow run completes. Fails this step (blocking the parent
  workflow) unless the child run concludes with success.

inputs:
  token:
    description: >
      PAT or GitHub App token with access to the target repo.
      The default GITHUB_TOKEN cannot dispatch cross-repo.
      Classic PAT: repo scope. Fine-grained: Contents R/W + Actions Read on the child.
    required: true
  target-repo:
    description: "Downstream repository in owner/repo form"
    required: true
  event-type:
    description: "event_type the child listens for under on.repository_dispatch.types"
    required: true
  client-payload:
    description: >
      JSON object string passed to the child as client_payload.
      GitHub caps client_payload at 10 top-level properties, so nest
      large input sets under a single key if needed. The action adds
      one key of its own: dispatch_id (used for run correlation).
    required: false
    default: "{}"
  poll-interval:
    description: "Seconds between status polls"
    required: false
    default: "15"
  startup-timeout:
    description: "Seconds to wait for the child run to appear before failing"
    required: false
    default: "180"
  timeout:
    description: "Seconds to wait for the child run to finish before failing"
    required: false
    default: "1800"

outputs:
  run-id:
    description: "Workflow run ID in the child repo"
    value: ${{ steps.wait.outputs.run-id }}
  run-url:
    description: "HTML URL of the child run"
    value: ${{ steps.wait.outputs.run-url }}
  conclusion:
    description: "Conclusion of the child run (success, failure, cancelled, ...)"
    value: ${{ steps.wait.outputs.conclusion }}

runs:
  using: "composite"
  steps:
    - id: wait
      shell: bash
      env:
        GH_TOKEN: ${{ inputs.token }}
        TARGET_REPO: ${{ inputs.target-repo }}
        EVENT_TYPE: ${{ inputs.event-type }}
        CLIENT_PAYLOAD: ${{ inputs.client-payload }}
        POLL_INTERVAL: ${{ inputs.poll-interval }}
        STARTUP_TIMEOUT: ${{ inputs.startup-timeout }}
        TIMEOUT: ${{ inputs.timeout }}
      run: |
        set -euo pipefail

        api() {
          curl -fsS \
            -H "Authorization: Bearer ${GH_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$@"
        }

        # 1) Unique correlation ID so we can find OUR run among any others.
        #    The dispatch endpoint returns 204 with no run id, so this is
        #    the only reliable way to correlate dispatch -> run.
        DISPATCH_ID=$(cat /proc/sys/kernel/random/uuid)
        echo "Dispatch ID: ${DISPATCH_ID}"

        # 2) Merge the caller's payload with the correlation ID.
        #    jq also validates that client-payload is valid JSON.
        PAYLOAD=$(jq -c --arg id "$DISPATCH_ID" '. + {dispatch_id: $id}' <<< "$CLIENT_PAYLOAD")
        BODY=$(jq -nc --arg et "$EVENT_TYPE" --argjson cp "$PAYLOAD" \
          '{event_type: $et, client_payload: $cp}')

        # Record a timestamp just BEFORE dispatching, to narrow the run search.
        SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        # 3) Fire the dispatch (expects HTTP 204).
        api -X POST "https://api.github.com/repos/${TARGET_REPO}/dispatches" -d "$BODY"
        echo "Dispatched '${EVENT_TYPE}' to ${TARGET_REPO}"

        # 4) Find the run this dispatch created. Requires the child workflow
        #    to include the dispatch_id in its run-name, e.g.:
        #      run-name: "Build · ${{ github.event.client_payload.dispatch_id }}"
        RUN_ID=""
        SECONDS=0
        while [ -z "$RUN_ID" ]; do
          if [ "$SECONDS" -ge "$STARTUP_TIMEOUT" ]; then
            echo "::error::Child run never appeared after ${STARTUP_TIMEOUT}s. Verify the child's on.repository_dispatch.types includes '${EVENT_TYPE}' and its run-name embeds client_payload.dispatch_id."
            exit 1
          fi
          sleep 5
          RUN_ID=$(api "https://api.github.com/repos/${TARGET_REPO}/actions/runs?event=repository_dispatch&created=%3E%3D${SINCE}&per_page=50" \
            | jq -r --arg id "$DISPATCH_ID" \
                '[.workflow_runs[] | select((.display_title // "") | contains($id))][0].id // empty')
        done

        RUN_URL="https://github.com/${TARGET_REPO}/actions/runs/${RUN_ID}"
        echo "Found child run: ${RUN_URL}"
        echo "run-id=${RUN_ID}" >> "$GITHUB_OUTPUT"
        echo "run-url=${RUN_URL}" >> "$GITHUB_OUTPUT"

        # 5) Poll the run until it completes; gate on conclusion.
        SECONDS=0
        while true; do
          if [ "$SECONDS" -ge "$TIMEOUT" ]; then
            echo "::error::Timed out after ${TIMEOUT}s waiting for ${RUN_URL}"
            exit 1
          fi

          RUN=$(api "https://api.github.com/repos/${TARGET_REPO}/actions/runs/${RUN_ID}")
          STATUS=$(jq -r '.status' <<< "$RUN")
          CONCLUSION=$(jq -r '.conclusion // empty' <<< "$RUN")
          echo "status=${STATUS} conclusion=${CONCLUSION:-n/a} elapsed=${SECONDS}s"

          if [ "$STATUS" = "completed" ]; then
            echo "conclusion=${CONCLUSION}" >> "$GITHUB_OUTPUT"
            if [ "$CONCLUSION" = "success" ]; then
              echo "Child run succeeded: ${RUN_URL}"
              exit 0
            fi
            echo "::error::Child run concluded '${CONCLUSION}': ${RUN_URL}"
            exit 1
          fi

          sleep "$POLL_INTERVAL"
        done
