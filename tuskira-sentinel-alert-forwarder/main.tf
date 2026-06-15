data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

locals {
  prefix = "tsk-${var.tenant_name}-${var.environment}"
}
