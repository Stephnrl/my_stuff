name: "Generate POA&M from Trivy"
description: "Parse Trivy JSON results and generate POA&M CSV/JSON artifacts"

inputs:
  trivy_json:
    description: "Path to Trivy JSON output"
    required: true

  image:
    description: "Image name/tag scanned"
    required: true

  output_csv:
    description: "Output POA&M CSV path"
    required: false
    default: "poam.csv"

  output_json:
    description: "Output normalized POA&M JSON path"
    required: false
    default: "poam.json"

  owner:
    description: "Default owning team"
    required: false
    default: "DevSecOps"

  min_severity:
    description: "Minimum severity to include: UNKNOWN, LOW, MEDIUM, HIGH, CRITICAL"
    required: false
    default: "HIGH"

  review_cycle:
    description: "Review cadence"
    required: false
    default: "monthly"

runs:
  using: "composite"
  steps:
    - name: Generate POA&M
      shell: bash
      run: |
        python "${{ github.action_path }}/poam_from_trivy.py" \
          --input "${{ inputs.trivy_json }}" \
          --image "${{ inputs.image }}" \
          --output-csv "${{ inputs.output_csv }}" \
          --output-json "${{ inputs.output_json }}" \
          --owner "${{ inputs.owner }}" \
          --min-severity "${{ inputs.min_severity }}" \
          --review-cycle "${{ inputs.review_cycle }}"
