# Ships ACR push events into the workspace so the coverage-gap alert can
# reconcile "images that exist" against "images that were gated".
#
# You said you are not creating the ACR - this only attaches a diagnostic
# setting to the existing one, which is additive and safe. Set acr_id to skip.

resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.enable_coverage_alert && var.acr_id != "" ? 1 : 0

  name                       = "diag-${local.name_prefix}-acr"
  target_resource_id         = var.acr_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.gate.id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = false
  }
}
