resource "azurerm_key_vault" "main" {
  name                       = "${var.tenant_name}-${var.environment}-fwd-kv"
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = var.tags
}

# Grant the deployer (current principal) access to manage secrets
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "Set", "Delete", "List", "Purge"]
}

resource "azurerm_key_vault_secret" "api_url" {
  name         = "tuskira-api-url"
  value        = var.api_url
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "api_key" {
  name         = "tuskira-api-key"
  value        = var.api_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}
