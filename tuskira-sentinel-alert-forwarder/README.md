# Tuskira Sentinel Alert Forwarder

Terraform module that connects Microsoft Sentinel to the Tuskira platform. When Sentinel creates an incident, an Azure Logic App automatically forwards the alert details to your Tuskira API endpoint.

## What gets deployed

| Resource | Purpose |
|----------|---------|
| Logic App (Consumption) | Listens for Sentinel incidents and POSTs alerts to Tuskira |
| User-Assigned Managed Identity | Authenticates the Logic App to Sentinel and Key Vault |
| Key Vault | Stores your Tuskira API URL and API key |
| API Connections | Connects the Logic App to Sentinel and Key Vault via managed identity |
| Role Assignments | Grants the Logic App access to read Sentinel data and read Key Vault secrets |
| Automation Rules (optional) | Triggers the Logic App when specific analytic rules fire |

## Prerequisites

1. **Azure resource group** — an existing resource group to deploy into
2. **Microsoft Sentinel** — enabled on a Log Analytics workspace
3. **Tuskira API credentials** — your API endpoint URL and Bearer token (provided by Tuskira)
4. **Terraform** >= 1.5.0
5. **Azure CLI** — authenticated with sufficient permissions:
   - Contributor on the resource group
   - Microsoft Sentinel Contributor on the workspace
   - Application Administrator or equivalent (to read service principals)

## Quick start

### 1. Create your Terraform config

Create a new directory for your deployment and add a `main.tf`:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.100" }
    azapi   = { source = "Azure/azapi",       version = "~> 1.12" }
    azuread = { source = "hashicorp/azuread",  version = "~> 2.47" }
  }
}

provider "azurerm" {
  features {
    key_vault { purge_soft_delete_on_destroy = false }
  }
}
provider "azapi" {}
provider "azuread" {}

module "sentinel_forwarder" {
  source = "git::ssh://git@bitbucket.org/deepinsight-team/tuskira-sentinel-alert-forwarder.git?ref=main"

  tenant_name                = "your-company"
  environment                = "prod"
  resource_group_name        = "rg-tuskira-your-company-prod"
  location                   = "australiaeast"
  log_analytics_workspace_id = "/subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.OperationalInsights/workspaces/WORKSPACE"
  api_url                    = var.api_url
  api_key                    = var.api_key
}

variable "api_url" { type = string }
variable "api_key" { type = string; sensitive = true }

output "logic_app_name" { value = module.sentinel_forwarder.logic_app_name }
```

### 2. Create a `terraform.tfvars` file (do not commit this)

```hcl
api_url = "https://your-company.tuskira.ai/api/v2/alerts"
api_key = "your-tuskira-api-key"
```

### 3. Deploy

```bash
terraform init
terraform apply
```

### 4. Choose how alerts are forwarded

You have two options for connecting Sentinel analytic rules to the Logic App:

**Option A: Sentinel Portal UI (recommended for getting started)**

Leave `enable_automation_rules` as `false` (the default). Then in the Azure Portal:

1. Go to **Microsoft Sentinel** > **Automation**
2. Click **Create** > **Automation rule**
3. Set trigger to **When incident is created**
4. Under Actions, select **Run playbook** and choose the Logic App (look for the name from the `logic_app_name` output)
5. Optionally add conditions to filter by analytic rule, severity, etc.

**Option B: Terraform-managed automation rules**

Add these variables to automatically create automation rules for specific analytic rules:

```hcl
module "sentinel_forwarder" {
  # ... other variables ...

  enable_automation_rules = true
  alert_rule_ids = [
    "/subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.OperationalInsights/workspaces/WS/providers/Microsoft.SecurityInsights/alertRules/RULE_NAME",
  ]
}
```

To find your analytic rule IDs:
```bash
az sentinel alert-rule list \
  --workspace-name WORKSPACE \
  --resource-group RG \
  --query "[].{name:name, displayName:displayName, id:id}" \
  -o table
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `tenant_name` | Short name for your company (used in Azure resource names) | `string` | — | yes |
| `resource_group_name` | Name of the Azure resource group to deploy into | `string` | — | yes |
| `log_analytics_workspace_id` | Full resource ID of the Log Analytics workspace with Sentinel | `string` | — | yes |
| `api_url` | Tuskira API endpoint URL | `string` | — | yes |
| `api_key` | Tuskira API Bearer token (stored in Key Vault) | `string` | — | yes |
| `environment` | Environment name (dev, staging, prod) | `string` | `"dev"` | no |
| `location` | Azure region for deployed resources | `string` | `"australiaeast"` | no |
| `enable_automation_rules` | Create automation rules via Terraform (see Option B above) | `bool` | `false` | no |
| `alert_rule_ids` | List of analytic rule resource IDs to forward (only when `enable_automation_rules = true`) | `list(string)` | `[]` | no |
| `tags` | Tags applied to all Azure resources | `map(string)` | `{managed_by, component}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `logic_app_id` | Resource ID of the deployed Logic App |
| `logic_app_name` | Name of the Logic App (use this to find it in the Sentinel Playbooks list) |
| `managed_identity_principal_id` | Principal ID of the Logic App's managed identity |
| `key_vault_name` | Name of the Key Vault storing API credentials |
| `key_vault_uri` | URI of the Key Vault |
| `automation_rule_ids` | IDs of created automation rules (empty if using Portal UI) |

## Updating API credentials

If you need to rotate your Tuskira API key, update the `api_key` variable and run `terraform apply`. The new value will be stored in Key Vault and the Logic App will use it on the next run.

## Troubleshooting

**Logic App runs show "Forbidden" errors**
- The managed identity may not have the correct role assignments. Run `terraform apply` again to ensure roles are in place.
- Check that the `Microsoft Sentinel Responder` role is assigned on the workspace.

**Automation rules fail to create with "Missing required permissions"**
- This module automatically grants the Azure Security Insights service principal access to the Logic App. If this fails, ensure your Terraform identity has permission to create role assignments.

**Alerts are not being forwarded**
- Verify the analytic rule is enabled and creating incidents in Sentinel.
- Check that an automation rule (either Portal-managed or Terraform-managed) is linked to the analytic rule.
- Check the Logic App run history in the Azure Portal for errors.

**Key Vault access denied**
- The module creates a Key Vault access policy for the Logic App's managed identity. If the policy was deleted, run `terraform apply` to recreate it.

## Architecture

```
Sentinel Analytic Rule
    |
    v (incident created)
Automation Rule
    |
    v (triggers playbook)
Logic App
    |--- reads API credentials from Key Vault
    |--- extracts alerts from incident
    |--- base64-encodes each alert
    |
    v (HTTP POST)
Tuskira API (/api/v2/alerts)
```
