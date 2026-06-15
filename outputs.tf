output "logic_app_id" {
  description = "Resource ID of the Logic App"
  value       = azurerm_logic_app_workflow.alert_forwarder.id
}

output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azurerm_logic_app_workflow.alert_forwarder.name
}

output "managed_identity_principal_id" {
  description = "Principal ID of the Logic App managed identity"
  value       = azurerm_user_assigned_identity.logic_app.principal_id
}

output "key_vault_name" {
  description = "Name of the Key Vault storing API credentials"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "automation_rule_ids" {
  description = "IDs of created automation rules (empty if Portal-managed)"
  value       = [for r in azurerm_sentinel_automation_rule.forward_alerts : r.id]
}
