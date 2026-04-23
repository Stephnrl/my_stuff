name: Launch AAP Job Template
description: >
  Launches a Red Hat Ansible Automation Platform 2.5 job template via the
  controller REST API, polls until terminal, and surfaces job ID + status.
  Backed by a PowerShell module (./AAP) for testability.

inputs:
  aap-url:
    description: Base URL of the AAP controller (e.g. https://aap.example.gov). No trailing slash required.
    required: true
  aap-token:
    description: OAuth2 bearer token for an AAP service user.
    required: true
  job-template:
    description: Numeric job template ID, or the JT name (resolved via API).
    required: true
  limit:
    description: Inventory limit pattern (typically a hostname).
    required: false
    default: ""
  extra-vars:
    description: JSON object of extra_vars to pass to the job template.
    required: false
    default: "{}"
  inventory:
    description: Inventory ID or name to override the JT default.
    required: false
    default: ""
  timeout-seconds:
    description: Max seconds to wait for the job to reach terminal state.
    required: false
    default: "3600"
  poll-interval-seconds:
    description: Seconds between status polls.
    required: false
    default: "15"
  fail-on-job-failure:
    description: If "true", fail the workflow when the AAP job fails.
    required: false
    default: "true"

outputs:
  job-id:
    description: Numeric AAP job ID.
    value: ${{ steps.run.outputs.job-id }}
  job-url:
    description: Direct link to the job in the AAP UI.
    value: ${{ steps.run.outputs.job-url }}
  status:
    description: Final job status (successful, failed, error, canceled).
    value: ${{ steps.run.outputs.status }}

runs:
  using: composite
  steps:
    - name: Launch AAP job
      id: run
      shell: pwsh
      working-directory: ${{ github.action_path }}
      env:
        # Composite actions don't auto-expose `with:` values to nested scripts, so we
        # forward them explicitly as INPUT_* env vars (the same convention GHA uses
        # internally for JS/Docker actions, which makes entrypoint.ps1 portable).
        INPUT_AAP_URL:               ${{ inputs.aap-url }}
        INPUT_AAP_TOKEN:             ${{ inputs.aap-token }}
        INPUT_JOB_TEMPLATE:          ${{ inputs.job-template }}
        INPUT_LIMIT:                 ${{ inputs.limit }}
        INPUT_EXTRA_VARS:            ${{ inputs.extra-vars }}
        INPUT_INVENTORY:             ${{ inputs.inventory }}
        INPUT_TIMEOUT_SECONDS:       ${{ inputs.timeout-seconds }}
        INPUT_POLL_INTERVAL_SECONDS: ${{ inputs.poll-interval-seconds }}
        INPUT_FAIL_ON_JOB_FAILURE:   ${{ inputs.fail-on-job-failure }}
      run: ./src/entrypoint.ps1
