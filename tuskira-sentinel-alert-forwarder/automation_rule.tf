resource "azurerm_sentinel_automation_rule" "forward_alerts" {
  for_each = var.enable_automation_rules ? toset(var.alert_rule_ids) : toset([])

  name                       = uuidv5("dns", each.value)
  log_analytics_workspace_id = var.log_analytics_workspace_id
  display_name               = "Forward to Tuskira – ${element(split("/", each.value), length(split("/", each.value)) - 1)}"
  order                      = 1
  enabled                    = true

  condition_json = jsonencode([{
    conditionProperties = {
      operator       = "Contains"
      propertyName   = "IncidentRelatedAnalyticRuleIds"
      propertyValues = [each.value]
    }
    conditionType = "Property"
  }])

  action_playbook {
    logic_app_id = azurerm_logic_app_workflow.alert_forwarder.id
    order        = 1
    tenant_id    = data.azurerm_client_config.current.tenant_id
  }

  depends_on = [azapi_resource_action.logic_app_definition]
}
