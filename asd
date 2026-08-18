# Telemetry pipeline: gate run -> Logs Ingestion API -> DCE -> DCR -> custom table.
#
# Verify Data Collection Rule and Logs Ingestion API availability in your Gov
# region before relying on this. Azure Monitor features reach Government after
# commercial, and this is the piece most likely to be missing.

resource "azurerm_log_analytics_workspace" "gate" {
  name                = "log-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

# Custom table. Column names here must match the keys emitted by
# poam/telemetry.py::build_event exactly, and the KQL alerts depend on both.
# Changing a name is a three-file edit.
resource "azapi_resource" "gate_table" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "SecurityGate_CL"
  parent_id = azurerm_log_analytics_workspace.gate.id

  body = {
    properties = {
      schema = {
        name = "SecurityGate_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "ComponentId", type = "string" },
          { name = "Repository", type = "string" },
          { name = "ImageDigest", type = "string" },
          { name = "ImageTag", type = "string" },
          { name = "ImageRef", type = "string" },
          { name = "GateResult", type = "string" },
          { name = "BypassUsed", type = "boolean" },
          { name = "BypassActor", type = "string" },
          { name = "BypassReason", type = "string" },
          { name = "IsInitialScan", type = "boolean" },
          { name = "PolicyProfile", type = "string" },
          { name = "PolicyFingerprint", type = "string" },
          { name = "GateVersion", type = "string" },
          { name = "TrivyVersion", type = "string" },
          { name = "VulnDbUpdatedAt", type = "string" },
          { name = "VulnDbAgeHours", type = "real" },
          { name = "NewCount", type = "int" },
          { name = "ClosedCount", type = "int" },
          { name = "ReopenedCount", type = "int" },
          { name = "PersistingCount", type = "int" },
          { name = "TotalOpen", type = "int" },
          { name = "OverdueCount", type = "int" },
          { name = "EscalationCount", type = "int" },
          { name = "CriticalOpen", type = "int" },
          { name = "HighOpen", type = "int" },
          { name = "MediumOpen", type = "int" },
          { name = "LowOpen", type = "int" },
          { name = "CriticalOpenIncludingDeviations", type = "int" },
          { name = "HighOpenIncludingDeviations", type = "int" },
          { name = "NewCritical", type = "int" },
          { name = "NewHigh", type = "int" },
          { name = "DeviationsActive", type = "int" },
          { name = "DeviationsExpiringSoon", type = "int" },
          { name = "DeviationsExpired", type = "int" },
          { name = "DeviationsRejected", type = "int" },
          { name = "ViolationCount", type = "int" },
          { name = "ViolationSummary", type = "string" },
          { name = "RunId", type = "string" },
          { name = "RunUrl", type = "string" },
          { name = "Actor", type = "string" },
          { name = "CommitSha", type = "string" },
          { name = "DurationSeconds", type = "real" },
          { name = "PoamUri", type = "string" },
          { name = "SbomUri", type = "string" },
        ]
      }
      retentionInDays      = var.log_retention_days
      totalRetentionInDays = var.log_total_retention_days
    }
  }

  schema_validation_enabled = false
}

resource "azurerm_monitor_data_collection_endpoint" "gate" {
  name                          = "dce-${local.name_prefix}"
  resource_group_name           = azurerm_resource_group.gate.name
  location                      = azurerm_resource_group.gate.location
  public_network_access_enabled = var.dce_public_access
  description                   = "Ingestion endpoint for container security gate telemetry"
  tags                          = local.tags
}

resource "azurerm_monitor_data_collection_rule" "gate" {
  name                        = "dcr-${local.name_prefix}"
  resource_group_name         = azurerm_resource_group.gate.name
  location                    = azurerm_resource_group.gate.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.gate.id
  tags                        = local.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.gate.id
      name                  = "gate-workspace"
    }
  }

  data_flow {
    streams       = ["Custom-SecurityGate_CL"]
    destinations  = ["gate-workspace"]
    output_stream = "Custom-SecurityGate_CL"
    transform_kql = "source"
  }

  stream_declaration {
    stream_name = "Custom-SecurityGate_CL"

    dynamic "column" {
      for_each = local.gate_stream_columns
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }

  depends_on = [azapi_resource.gate_table]
}

locals {
  # Stream declaration mirrors the table schema. Kept as a local so the two
  # cannot drift apart silently.
  gate_stream_columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "ComponentId", type = "string" },
    { name = "Repository", type = "string" },
    { name = "ImageDigest", type = "string" },
    { name = "ImageTag", type = "string" },
    { name = "ImageRef", type = "string" },
    { name = "GateResult", type = "string" },
    { name = "BypassUsed", type = "boolean" },
    { name = "BypassActor", type = "string" },
    { name = "BypassReason", type = "string" },
    { name = "IsInitialScan", type = "boolean" },
    { name = "PolicyProfile", type = "string" },
    { name = "PolicyFingerprint", type = "string" },
    { name = "GateVersion", type = "string" },
    { name = "TrivyVersion", type = "string" },
    { name = "VulnDbUpdatedAt", type = "string" },
    { name = "VulnDbAgeHours", type = "real" },
    { name = "NewCount", type = "int" },
    { name = "ClosedCount", type = "int" },
    { name = "ReopenedCount", type = "int" },
    { name = "PersistingCount", type = "int" },
    { name = "TotalOpen", type = "int" },
    { name = "OverdueCount", type = "int" },
    { name = "EscalationCount", type = "int" },
    { name = "CriticalOpen", type = "int" },
    { name = "HighOpen", type = "int" },
    { name = "MediumOpen", type = "int" },
    { name = "LowOpen", type = "int" },
    { name = "CriticalOpenIncludingDeviations", type = "int" },
    { name = "HighOpenIncludingDeviations", type = "int" },
    { name = "NewCritical", type = "int" },
    { name = "NewHigh", type = "int" },
    { name = "DeviationsActive", type = "int" },
    { name = "DeviationsExpiringSoon", type = "int" },
    { name = "DeviationsExpired", type = "int" },
    { name = "DeviationsRejected", type = "int" },
    { name = "ViolationCount", type = "int" },
    { name = "ViolationSummary", type = "string" },
    { name = "RunId", type = "string" },
    { name = "RunUrl", type = "string" },
    { name = "Actor", type = "string" },
    { name = "CommitSha", type = "string" },
    { name = "DurationSeconds", type = "real" },
    { name = "PoamUri", type = "string" },
    { name = "SbomUri", type = "string" },
  ]
}

# The gate identity needs this to POST to the Logs Ingestion API.
resource "azurerm_role_assignment" "gate_metrics_publisher" {
  scope                = azurerm_monitor_data_collection_rule.gate.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.gate_principal_id
}

resource "azurerm_monitor_action_group" "security" {
  name                = "ag-${local.name_prefix}-security"
  resource_group_name = azurerm_resource_group.gate.name
  short_name          = substr(replace(var.name_prefix, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.security_email_receivers
    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.security_webhook_url == "" ? [] : [1]
    content {
      name                    = "teams"
      service_uri             = var.security_webhook_url
      use_common_alert_schema = true
    }
  }
}
