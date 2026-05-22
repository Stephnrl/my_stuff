  baseline_json:
    description: "Approved POA&M baseline JSON to compare against"
    required: false
    default: ""

  gate_mode:
    description: "Gate mode: off, warn, fail-on-new, fail-on-new-critical, fail-on-new-fixable"
    required: false
    default: "warn"

  delta_json:
    description: "Output delta JSON path"
    required: false
    default: "poam-delta.json"

  delta_csv:
    description: "Output delta CSV path"
    required: false
    default: "poam-delta.csv"
