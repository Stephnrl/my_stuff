output "storage_account_name" {
  description = "Set as the GATE_STORAGE_ACCOUNT repository variable."
  value       = azurerm_storage_account.gate.name
}

output "state_store_uri" {
  description = "Pass to the gate as state_store."
  value       = "az://${azurerm_storage_account.gate.name}/${azurerm_storage_container.poam.name}"
}

output "dce_endpoint" {
  description = "Set as the GATE_DCE_ENDPOINT repository variable."
  value       = azurerm_monitor_data_collection_endpoint.gate.logs_ingestion_endpoint
}

output "dcr_immutable_id" {
  description = "Set as the GATE_DCR_IMMUTABLE_ID repository variable."
  value       = azurerm_monitor_data_collection_rule.gate.immutable_id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.gate.id
}

output "action_group_id" {
  value = azurerm_monitor_action_group.security.id
}

output "github_variables" {
  description = "Copy these into GitHub org/repo variables."
  value = {
    GATE_STORAGE_ACCOUNT   = azurerm_storage_account.gate.name
    GATE_DCE_ENDPOINT      = azurerm_monitor_data_collection_endpoint.gate.logs_ingestion_endpoint
    GATE_DCR_IMMUTABLE_ID  = azurerm_monitor_data_collection_rule.gate.immutable_id
  }
}
