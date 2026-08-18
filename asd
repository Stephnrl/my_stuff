# Alert rules over SecurityGate_CL.
#
# Ordered roughly by value. The coverage alerts at the bottom matter most:
# they detect the ABSENCE of signal. Everything above them only fires when the
# gate ran, which means none of them catch the team that quietly stopped
# calling the workflow — the most common way these programs fail in practice.

locals {
  alert_scopes = [azurerm_log_analytics_workspace.gate.id]
}

# --- 1. Bypass used -------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "bypass_used" {
  name                = "alert-${local.name_prefix}-bypass-used"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 1
  scopes              = local.alert_scopes
  description         = "Emergency bypass was used to ship an image that failed the security gate."
  enabled             = true

  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"

  criteria {
    query                   = <<-KQL
      SecurityGate_CL
      | where BypassUsed == true
      | project TimeGenerated, ComponentId, ImageDigest, BypassActor, BypassReason, ViolationCount, RunUrl
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    dimension {
      name     = "ComponentId"
      operator = "Include"
      values   = ["*"]
    }
  }

  auto_mitigation_enabled = false
  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 2. New critical introduced -------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "new_critical" {
  name                = "alert-${local.name_prefix}-new-critical"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 2
  scopes              = local.alert_scopes
  description         = "A build introduced a new CRITICAL finding not covered by an approved deviation."

  evaluation_frequency = "PT15M"
  window_duration      = "PT30M"

  criteria {
    query                   = <<-KQL
      SecurityGate_CL
      | where NewCritical > 0
      | project TimeGenerated, ComponentId, ImageTag, NewCritical, GateResult, RunUrl
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    dimension {
      name     = "ComponentId"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 3. Regression: a closed finding came back ----------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "regression" {
  name                = "alert-${local.name_prefix}-regression"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 2
  scopes              = local.alert_scopes
  description         = "A previously remediated finding has reappeared. Often a base-image rollback."

  evaluation_frequency = "PT30M"
  window_duration      = "PT1H"

  criteria {
    query                   = <<-KQL
      SecurityGate_CL
      | where ReopenedCount > 0
      | project TimeGenerated, ComponentId, ImageTag, ReopenedCount, RunUrl
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    dimension {
      name     = "ComponentId"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 4. Deviations expiring ------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "deviations_expiring" {
  name                = "alert-${local.name_prefix}-deviations-expiring"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 3
  scopes              = local.alert_scopes
  description         = "Approved deviations expire soon. On expiry these findings start failing builds."

  evaluation_frequency = "PT6H"
  window_duration      = "P1D"

  criteria {
    query                   = <<-KQL
      SecurityGate_CL
      | where DeviationsExpiringSoon > 0 or DeviationsExpired > 0
      | summarize arg_max(TimeGenerated, DeviationsExpiringSoon, DeviationsExpired) by ComponentId
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    dimension {
      name     = "ComponentId"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 5. Overdue POA&M items ------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "overdue_items" {
  name                = "alert-${local.name_prefix}-overdue-poam"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 2
  scopes              = local.alert_scopes
  description         = "Open POA&M items are past their scheduled completion date."

  evaluation_frequency = "PT6H"
  window_duration      = "P1D"

  criteria {
    query                   = <<-KQL
      SecurityGate_CL
      | summarize arg_max(TimeGenerated, OverdueCount) by ComponentId
      | where OverdueCount > ${var.overdue_alert_threshold}
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    dimension {
      name     = "ComponentId"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 6. Trivy DB going stale ----------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "stale_db" {
  name                = "alert-${local.name_prefix}-stale-vuln-db"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 1
  scopes              = local.alert_scopes
  description         = "Scans ran against a stale vulnerability database. A stale DB passes images it should block."

  evaluation_frequency = "PT1H"
  window_duration      = "PT6H"

  criteria {
    query                   = <<-KQL
      SecurityGate_CL
      | where VulnDbAgeHours > ${var.max_db_age_hours}
      | project TimeGenerated, ComponentId, VulnDbAgeHours, VulnDbUpdatedAt, TrivyVersion
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 7. DB mirror heartbeat missing ---------------------------------------
# Fires on ABSENCE. A failing mirror job produces a failure signal; a DISABLED
# or deleted schedule produces nothing at all, and that is the dangerous case.

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "mirror_heartbeat_missing" {
  name                = "alert-${local.name_prefix}-db-mirror-silent"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 1
  scopes              = local.alert_scopes
  description         = "No trivy-db mirror heartbeat received. The mirror job may be disabled or deleted."

  evaluation_frequency = "PT1H"
  window_duration      = "PT12H"

  criteria {
    query                   = <<-KQL
      let expected = 1;
      let seen = toscalar(
        SecurityGate_CL
        | where ComponentId == "_infrastructure/trivy-db-mirror"
        | where TimeGenerated > ago(12h)
        | count
      );
      print MissingHeartbeat = iff(coalesce(seen, 0) == 0, 1, 0)
      | where MissingHeartbeat == 1
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 8. COVERAGE GAP: image pushed but never gated ------------------------
#
# The highest-value alert here. Everything above only fires when the gate RAN.
# This one reconciles ACR push events against gate events and catches the
# component that quietly stopped calling the workflow.
#
# Requires ACR diagnostic settings (ContainerRegistryRepositoryEvents) shipped
# to this workspace - see acr_diagnostics.tf.

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "coverage_gap" {
  count = var.enable_coverage_alert ? 1 : 0

  name                = "alert-${local.name_prefix}-coverage-gap"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 1
  scopes              = local.alert_scopes
  description         = "An image was pushed to ACR with no corresponding security gate run. This is a hole in the control."

  evaluation_frequency = "PT1H"
  window_duration      = "PT6H"

  criteria {
    query                   = <<-KQL
      let gated =
        SecurityGate_CL
        | where TimeGenerated > ago(24h)
        | project Digest = tolower(ImageDigest);
      ContainerRegistryRepositoryEvents
      | where TimeGenerated > ago(6h)
      | where OperationName in ("Push", "push")
      | where isnotempty(Digest)
      | where Repository !startswith "trivy/"          // mirror artifacts, not app images
      | extend Digest = tolower(Digest)
      | distinct Repository, Tag, Digest, LoginServer
      | join kind=leftanti gated on Digest
      | project Repository, Tag, Digest, LoginServer
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    dimension {
      name     = "Repository"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}

# --- 9. COVERAGE GAP: component went quiet --------------------------------
# A component that used to be scanned and no longer is. Catches a pipeline
# that was deleted or a repository that was archived without decommissioning.

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "component_went_quiet" {
  name                = "alert-${local.name_prefix}-component-quiet"
  resource_group_name = azurerm_resource_group.gate.name
  location            = azurerm_resource_group.gate.location
  severity            = 2
  scopes              = local.alert_scopes
  description         = "A component previously covered by the gate has not been scanned recently."

  evaluation_frequency = "P1D"
  window_duration      = "P1D"

  criteria {
    query                   = <<-KQL
      SecurityGate_CL
      | where TimeGenerated > ago(${var.component_quiet_lookback_days}d)
      | where ComponentId !startswith "_infrastructure/"
      | summarize LastSeen = max(TimeGenerated), Scans = count() by ComponentId
      | where Scans >= 3                                       // was genuinely active
      | where LastSeen < ago(${var.component_quiet_days}d)
      | extend DaysSilent = datetime_diff('day', now(), LastSeen)
      | project ComponentId, LastSeen, DaysSilent, Scans
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    dimension {
      name     = "ComponentId"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.security.id]
  }

  tags = local.tags
}
