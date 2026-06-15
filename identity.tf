resource "azurerm_user_assigned_identity" "logic_app" {
  name                = "${local.prefix}-alert-fwd-id"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  tags                = var.tags
}

# Grant Logic App identity access to read Key Vault secrets
resource "azurerm_key_vault_access_policy" "logic_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.logic_app.principal_id

  secret_permissions = ["Get"]
}

# Grant Logic App identity Microsoft Sentinel Responder role on the workspace
# Required for the Sentinel trigger to read alert data
resource "azurerm_role_assignment" "sentinel_responder" {
  scope                = var.log_analytics_workspace_id
  role_definition_name = "Microsoft Sentinel Responder"
  principal_id         = azurerm_user_assigned_identity.logic_app.principal_id
}

# Grant Azure Security Insights SP "Microsoft Sentinel Automation Contributor"
# on the Logic App so that automation rules can trigger it as a playbook.
# This is a well-known Microsoft first-party app (appId is constant across tenants).
data "azuread_service_principal" "security_insights" {
  client_id = "98785600-1bb7-4fb9-b9fa-19afe2c8a360" # Azure Security Insights
}

resource "azurerm_role_assignment" "sentinel_automation_contributor" {
  scope                = azurerm_logic_app_workflow.alert_forwarder.id
  role_definition_name = "Microsoft Sentinel Automation Contributor"
  principal_id         = data.azuread_service_principal.security_insights.object_id
}
