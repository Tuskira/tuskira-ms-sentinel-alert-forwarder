resource "azurerm_logic_app_workflow" "alert_forwarder" {
  name                = "${local.prefix}-sentinel-alert-fwd"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  tags                = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app.id]
  }

  workflow_parameters = {
    "$connections" = jsonencode({
      defaultValue = {}
      type         = "Object"
    })
  }

  parameters = {
    "$connections" = jsonencode({
      microsoftsentinel = {
        connectionId   = azapi_resource.sentinel_connection.id
        connectionName = azapi_resource.sentinel_connection.name
        id             = data.azurerm_managed_api.sentinel.id
        connectionProperties = {
          authentication = {
            type     = "ManagedServiceIdentity"
            identity = azurerm_user_assigned_identity.logic_app.id
          }
        }
      }
      keyvault = {
        connectionId   = azapi_resource.keyvault_connection.id
        connectionName = azapi_resource.keyvault_connection.name
        id             = data.azurerm_managed_api.keyvault.id
        connectionProperties = {
          authentication = {
            type     = "ManagedServiceIdentity"
            identity = azurerm_user_assigned_identity.logic_app.id
          }
        }
      }
    })
  }
}

# --- Managed API references ---

data "azurerm_managed_api" "sentinel" {
  name     = "azuresentinel"
  location = var.location
}

data "azurerm_managed_api" "keyvault" {
  name     = "keyvault"
  location = var.location
}

# --- API Connections ---

# Use azapi_resource for Sentinel connection — azurerm_api_connection hangs
# because it uses OAuth code flow. azapi lets us set parameterValueType = "Alternative"
# which enables managed identity auth without interactive consent.
resource "azapi_resource" "sentinel_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = "${local.prefix}-sentinel-conn"
  location  = var.location
  parent_id = data.azurerm_resource_group.main.id
  tags      = var.tags

  schema_validation_enabled = false

  body = jsonencode({
    properties = {
      api = {
        id = data.azurerm_managed_api.sentinel.id
      }
      displayName        = "Sentinel Alert Forwarder"
      parameterValueType = "Alternative"
      alternativeParameterValues = {
        "token:TenantId"  = data.azurerm_client_config.current.tenant_id
        "token:grantType" = "code"
      }
    }
  })

  lifecycle {
    ignore_changes = [body]
  }
}

resource "azapi_resource" "keyvault_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = "${local.prefix}-keyvault-conn"
  location  = var.location
  parent_id = data.azurerm_resource_group.main.id
  tags      = var.tags

  schema_validation_enabled = false

  body = jsonencode({
    properties = {
      api = {
        id = data.azurerm_managed_api.keyvault.id
      }
      displayName        = "Key Vault - Alert Forwarder"
      parameterValueType = "Alternative"
      alternativeParameterValues = {
        vaultName = azurerm_key_vault.main.name
      }
    }
  })

  lifecycle {
    ignore_changes = [body]
  }
}

# --- Extract workspace name from resource ID ---

locals {
  workspace_name = element(split("/", var.log_analytics_workspace_id), length(split("/", var.log_analytics_workspace_id)) - 1)
}

# --- Logic App Workflow Definition (using azapi for full control) ---

resource "azapi_resource_action" "logic_app_definition" {
  type        = "Microsoft.Logic/workflows@2019-05-01"
  resource_id = azurerm_logic_app_workflow.alert_forwarder.id
  method      = "PUT"

  body = jsonencode({
    location = var.location
    tags     = var.tags
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.logic_app.id) = {}
      }
    }
    properties = {
      state = "Enabled"
      definition = {
        "$schema"      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
        contentVersion = "1.0.0.0"

        parameters = {
          "$connections" = {
            defaultValue = {}
            type         = "Object"
          }
        }

        triggers = {
          "Microsoft_Sentinel_incident" = {
            type = "ApiConnectionWebhook"
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['microsoftsentinel']['connectionId']"
                }
              }
              body = {
                callback_url = "@{listCallbackUrl()}"
              }
              path = "/incident-creation"
            }
          }
        }

        actions = {
          "Initialize_run_id" = {
            type     = "InitializeVariable"
            runAfter = {}
            inputs = {
              variables = [{
                name  = "run_id"
                type  = "String"
                value = "@{guid()}"
              }]
            }
          }

          "Initialize_scanned_at" = {
            type     = "InitializeVariable"
            runAfter = { "Initialize_run_id" = ["Succeeded"] }
            inputs = {
              variables = [{
                name  = "scanned_at"
                type  = "String"
                value = "@{utcNow('yyyy-MM-ddTHH:mm:ss.fffZ')}"
              }]
            }
          }

          "Initialize_events_array" = {
            type     = "InitializeVariable"
            runAfter = { "Initialize_scanned_at" = ["Succeeded"] }
            inputs = {
              variables = [{
                name  = "events_array"
                type  = "Array"
                value = []
              }]
            }
          }

          "Get_api_url" = {
            type     = "ApiConnection"
            runAfter = { "Initialize_events_array" = ["Succeeded"] }
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['keyvault']['connectionId']"
                }
              }
              method = "get"
              path   = "/secrets/@{encodeURIComponent('tuskira-api-url')}/value"
            }
          }

          "Get_api_key" = {
            type     = "ApiConnection"
            runAfter = { "Initialize_events_array" = ["Succeeded"] }
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['keyvault']['connectionId']"
                }
              }
              method = "get"
              path   = "/secrets/@{encodeURIComponent('tuskira-api-key')}/value"
            }
          }

          "For_each_alert" = {
            type     = "Foreach"
            runAfter = { "Get_api_url" = ["Succeeded"], "Get_api_key" = ["Succeeded"] }
            foreach  = "@triggerBody()?['object']?['properties']?['Alerts']"
            operationOptions = "Sequential"
            actions = {
              "Compose_alert_event" = {
                type     = "Compose"
                runAfter = {}
                inputs = {
                  alert = "@items('For_each_alert')"
                  metadata = {
                    sentinel_workspace_id    = "@triggerBody()?['workspaceId']"
                    sentinel_subscription_id = "@triggerBody()?['workspaceInfo']?['SubscriptionId']"
                    sentinel_resource_group  = "@triggerBody()?['workspaceInfo']?['ResourceGroupName']"
                    sentinel_incident_number = "@triggerBody()?['object']?['properties']?['incidentNumber']"
                  }
                }
              }

              "Append_to_events_array" = {
                type     = "AppendToArrayVariable"
                runAfter = { "Compose_alert_event" = ["Succeeded"] }
                inputs = {
                  name  = "events_array"
                  value = {
                    alert_type = "SENTINEL_ALERT"
                    scanned_at = "@variables('scanned_at')"
                    source     = "tuskira-sentinel-logic-app"
                    data       = "@{base64(string(outputs('Compose_alert_event')))}"
                  }
                }
              }
            }
          }

          "Compose_payload" = {
            type     = "Compose"
            runAfter = { "For_each_alert" = ["Succeeded"] }
            inputs = {
              run_id             = "@variables('run_id')"
              stream_id          = "sentinel-alerts"
              batch_sequence_num = 1
              events             = "@variables('events_array')"
            }
          }

          "POST_to_Tuskira_API" = {
            type     = "Http"
            runAfter = { "Compose_payload" = ["Succeeded"] }
            inputs = {
              method = "POST"
              uri    = "@body('Get_api_url')?['value']"
              headers = {
                "Content-Type"  = "application/json"
                "Authorization" = "Bearer @{body('Get_api_key')?['value']}"
              }
              body = "@outputs('Compose_payload')"
              retryPolicy = {
                type     = "fixed"
                count    = 3
                interval = "PT30S"
              }
            }
          }

          "Check_response" = {
            type     = "If"
            runAfter = { "POST_to_Tuskira_API" = ["Succeeded", "Failed"] }
            expression = {
              and = [{
                equals = ["@outputs('POST_to_Tuskira_API')['statusCode']", 200]
              }]
            }
            actions = {
              "Log_success" = {
                type = "Compose"
                inputs = {
                  status   = "success"
                  run_id   = "@variables('run_id')"
                  response = "@body('POST_to_Tuskira_API')"
                }
              }
            }
            else = {
              actions = {
                "Log_failure" = {
                  type = "Compose"
                  inputs = {
                    status      = "error"
                    run_id      = "@variables('run_id')"
                    status_code = "@outputs('POST_to_Tuskira_API')['statusCode']"
                    error       = "@body('POST_to_Tuskira_API')"
                  }
                }
              }
            }
          }
        }

        outputs = {}
      }
      parameters = {
        "$connections" = {
          value = {
            microsoftsentinel = {
              connectionId   = azapi_resource.sentinel_connection.id
              connectionName = azapi_resource.sentinel_connection.name
              id             = data.azurerm_managed_api.sentinel.id
              connectionProperties = {
                authentication = {
                  type     = "ManagedServiceIdentity"
                  identity = azurerm_user_assigned_identity.logic_app.id
                }
              }
            }
            keyvault = {
              connectionId   = azapi_resource.keyvault_connection.id
              connectionName = azapi_resource.keyvault_connection.name
              id             = data.azurerm_managed_api.keyvault.id
              connectionProperties = {
                authentication = {
                  type     = "ManagedServiceIdentity"
                  identity = azurerm_user_assigned_identity.logic_app.id
                }
              }
            }
          }
        }
      }
    }
  })

  depends_on = [
    azurerm_logic_app_workflow.alert_forwarder,
    azapi_resource.sentinel_connection,
    azapi_resource.keyvault_connection,
  ]
}
