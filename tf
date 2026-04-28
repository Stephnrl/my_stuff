locals {
  # If the caller didn't provide a numeric job_template_id, look it up by name+org.
  use_data_source = var.job_template_id == null

  # Validation: caller must give us either an ID or a (name, organization) pair.
  _validate_inputs = (
    var.job_template_id != null
    || (var.job_template_name != null && var.job_template_organization != null)
  ) ? true : tobool("Either job_template_id, or both job_template_name and job_template_organization, must be set.")

  resolved_job_template_id = local.use_data_source ? data.aap_job_template.this[0].id : var.job_template_id

  # AAP wants extra_vars as a JSON (or YAML) string.
  # Merge non-sensitive and sensitive vars; result inherits the sensitive mark.
  merged_extra_vars  = merge(var.extra_vars, var.sensitive_extra_vars)
  encoded_extra_vars = jsonencode(local.merged_extra_vars)

  # Build the triggers map. Any change to any value here causes a rerun.
  #   - extra_triggers:        caller-supplied (e.g. upstream resource IDs)
  #   - rerun_token:           manual knob
  #   - extra_vars_sha256:     auto-rerun when public payload changes
  #   - sensitive_vars_sha256: auto-rerun when secret payload changes (hash only,
  #                            never the raw value — safe to land in state)
  triggers = merge(
    var.extra_triggers,
    var.rerun_token == "" ? {} : { rerun_token = var.rerun_token },
    var.rerun_on_extra_vars_change ? {
      extra_vars_sha256     = sha256(jsonencode(var.extra_vars))
      sensitive_vars_sha256 = sha256(jsonencode(var.sensitive_extra_vars))
    } : {},
  )
}

data "aap_job_template" "this" {
  count = local.use_data_source ? 1 : 0

  name              = var.job_template_name
  organization_name = var.job_template_organization
}

resource "aap_job" "this" {
  job_template_id = local.resolved_job_template_id
  inventory_id    = var.inventory_id
  extra_vars      = local.encoded_extra_vars

  wait_for_completion                 = var.wait_for_completion
  wait_for_completion_timeout_seconds = var.wait_for_completion_timeout_seconds

  triggers = local.triggers
}
