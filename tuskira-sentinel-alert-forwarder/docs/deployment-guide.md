---
title: "Tuskira Sentinel Alert Forwarder - Deployment Guide"
subtitle: "Customer Setup and Configuration"
date: "March 2026"
---

# Tuskira Sentinel Alert Forwarder

## Deployment Guide

---

## 1. Overview

The Tuskira Sentinel Alert Forwarder is a Terraform module that automatically forwards Microsoft Sentinel alerts to the Tuskira platform. When Sentinel creates an incident from an analytic rule, an Azure Logic App extracts the alert details and sends them to your Tuskira API endpoint. All credentials are stored securely in Azure Key Vault.

### Architecture

```
  Microsoft Sentinel
        |
        | (incident created by analytic rule)
        v
  Automation Rule
        |
        | (triggers playbook)
        v
  Azure Logic App
        |
        |--- Reads API credentials from Azure Key Vault
        |--- Extracts alert details from the incident
        |--- Base64-encodes each alert
        |
        v (HTTPS POST)
  Tuskira API  (/api/v2/alerts)
```

### Resources Deployed

| Resource | Name Pattern | Purpose |
|----------|-------------|---------|
| User-Assigned Managed Identity | `tsk-{tenant}-{env}-alert-fwd-id` | Authenticates Logic App to Sentinel and Key Vault |
| Logic App (Consumption) | `tsk-{tenant}-{env}-sentinel-alert-fwd` | Processes incidents and forwards alerts to Tuskira |
| Key Vault | `{tenant}-{env}-fwd-kv` | Stores Tuskira API URL and API key |
| Sentinel API Connection | `tsk-{tenant}-{env}-sentinel-conn` | Connects Logic App to Microsoft Sentinel |
| Key Vault API Connection | `tsk-{tenant}-{env}-keyvault-conn` | Connects Logic App to Key Vault |
| Automation Rules (optional) | `Forward to Tuskira - {rule}` | Triggers the Logic App for specific analytic rules |

---

## 2. Prerequisites

Before deploying, ensure you have the following:

### Azure Resources (must already exist)

- **Azure Resource Group** - A resource group where the forwarder resources will be deployed
- **Log Analytics Workspace** - With Microsoft Sentinel enabled
- **Microsoft Sentinel** - Enabled on the workspace with at least one active analytic rule

### Tuskira Credentials

Contact your Tuskira representative to obtain:

- **API URL** - Your Tuskira API endpoint (e.g., `https://your-company.tuskira.ai/api/v2/alerts`)
- **API Key** - A Bearer token for authenticating API requests

### Tools

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Terraform | 1.5.0 | Infrastructure deployment |
| Azure CLI | 2.50+ | Azure authentication |
| Git | Any | Cloning the module repository |

### Azure CLI Authentication

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

---

## 3. Required Azure Permissions

The user or service principal running `terraform apply` must have the following permissions.

### Recommended: Built-in Role Assignments

The simplest approach is to assign these built-in roles:

| Role | Scope | Why |
|------|-------|-----|
| **Contributor** | Resource Group | Creates Logic App, Key Vault, managed identity, API connections, secrets |
| **User Access Administrator** | Resource Group | Creates role assignments for the managed identity and Azure Security Insights SP |
| **Microsoft Sentinel Contributor** | Log Analytics Workspace | Creates automation rules (only if using Terraform-managed rules) |
| **Directory Readers** | Azure AD Tenant | Reads the Azure Security Insights service principal |

### How to Assign These Roles

**Resource Group roles:**

```bash
# Replace with your values
DEPLOYER_ID="<your-user-or-sp-object-id>"
RG_SCOPE="/subscriptions/<sub-id>/resourceGroups/<rg-name>"

az role assignment create --assignee $DEPLOYER_ID \
  --role "Contributor" --scope $RG_SCOPE

az role assignment create --assignee $DEPLOYER_ID \
  --role "User Access Administrator" --scope $RG_SCOPE
```

**Sentinel Contributor on workspace (only if using Terraform-managed automation rules):**

```bash
WORKSPACE_SCOPE="/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>"

az role assignment create --assignee $DEPLOYER_ID \
  --role "Microsoft Sentinel Contributor" --scope $WORKSPACE_SCOPE
```

**Azure AD Directory Readers:**

```bash
# This requires a Global Administrator or Privileged Role Administrator
az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/directoryRoles/roleTemplateId=88d8e3e3-8f55-4a1e-953a-9b9898b8876b/members/\$ref" \
  --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/$DEPLOYER_ID\"}"
```

### Detailed Permission Breakdown

For organizations that prefer custom roles or need to understand exactly what is required:

| Azure Resource | Permission | Scope |
|---------------|------------|-------|
| Resource Group | `Microsoft.Resources/subscriptions/resourceGroups/read` | Resource Group |
| Managed Identity | `Microsoft.ManagedIdentity/userAssignedIdentities/*` | Resource Group |
| Logic App | `Microsoft.Logic/workflows/*` | Resource Group |
| API Connections | `Microsoft.Web/connections/*` | Resource Group |
| Key Vault | `Microsoft.KeyVault/vaults/*` | Resource Group |
| Key Vault Secrets | `Microsoft.KeyVault/vaults/secrets/*` | Key Vault |
| Role Assignments | `Microsoft.Authorization/roleAssignments/write` | Resource Group + Workspace |
| Managed APIs | `Microsoft.Web/locations/managedApis/read` | Subscription |
| Sentinel Rules | `Microsoft.SecurityInsights/automationRules/*` | Workspace (if using TF rules) |
| Azure AD | `microsoft.directory/servicePrincipals/read` | Tenant |

---

## 4. Deployment Steps

### Step 1: Create Your Deployment Directory

```bash
mkdir sentinel-forwarder-deploy
cd sentinel-forwarder-deploy
```

### Step 2: Create `main.tf`

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

variable "api_url" {
  description = "Tuskira API endpoint URL"
  type        = string
}

variable "api_key" {
  description = "Tuskira API Bearer token"
  type        = string
  sensitive   = true
}

module "sentinel_forwarder" {
  source = "git::ssh://git@bitbucket.org/deepinsight-team/tuskira-sentinel-alert-forwarder.git?ref=main"

  # --- Required: Update these values ---
  tenant_name                = "your-company"
  environment                = "prod"
  resource_group_name        = "your-resource-group"
  location                   = "australiaeast"
  log_analytics_workspace_id = "/subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.OperationalInsights/workspaces/WORKSPACE"

  api_url = var.api_url
  api_key = var.api_key

  # --- Optional: Terraform-managed automation rules ---
  # enable_automation_rules = true
  # alert_rule_ids = [
  #   "/subscriptions/.../alertRules/RULE_NAME",
  # ]
}

output "logic_app_name" {
  value = module.sentinel_forwarder.logic_app_name
}

output "logic_app_id" {
  value = module.sentinel_forwarder.logic_app_id
}
```

**Replace the following values:**

| Placeholder | Where to Find It |
|-------------|-----------------|
| `your-company` | A short identifier for your organization |
| `prod` | Your environment name (dev, staging, prod) |
| `your-resource-group` | Azure Portal > Resource Groups |
| `australiaeast` | Your preferred Azure region |
| `log_analytics_workspace_id` | Azure Portal > Log Analytics Workspaces > Properties > Resource ID |

### Step 3: Create `terraform.tfvars`

Create a file named `terraform.tfvars` with your Tuskira credentials. **Do not commit this file to version control.**

```hcl
api_url = "https://your-company.tuskira.ai/api/v2/alerts"
api_key = "your-tuskira-api-key"
```

### Step 4: Initialize and Deploy

```bash
terraform init
terraform plan       # Review what will be created
terraform apply      # Deploy (type 'yes' to confirm)
```

Expected output after successful deployment:

```
Apply complete! Resources: 16 added, 0 changed, 0 destroyed.

Outputs:

logic_app_name = "tsk-your-company-prod-sentinel-alert-fwd"
logic_app_id   = "/subscriptions/.../workflows/tsk-your-company-prod-sentinel-alert-fwd"
```

### Step 5: Connect Analytic Rules to the Forwarder

You have two options:

#### Option A: Sentinel Portal UI (Recommended for Getting Started)

1. Open **Azure Portal** > **Microsoft Sentinel** > your workspace
2. Go to **Automation** in the left menu
3. Click **Create** > **Automation rule**
4. Configure:
   - **Name**: e.g., "Forward alerts to Tuskira"
   - **Trigger**: "When incident is created"
   - **Conditions** (optional): Filter by analytic rule name, severity, etc.
   - **Actions**: Select **Run playbook**, then choose the Logic App name from the `logic_app_name` output
5. Click **Apply**

#### Option B: Terraform-Managed Automation Rules

Uncomment the automation rule variables in your `main.tf`:

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
  --workspace-name YOUR_WORKSPACE \
  --resource-group YOUR_RG \
  --query "[].{name:name, displayName:displayName}" \
  -o table
```

Then run `terraform apply` again.

---

## 5. Verification

### Check the Logic App

1. **Azure Portal** > **Resource Groups** > your resource group
2. Find the Logic App (name starts with `tsk-`)
3. Verify **Status** is "Enabled"
4. Check the **Trigger** shows "Microsoft_Sentinel_incident"

### Check Automation Rules

1. **Azure Portal** > **Microsoft Sentinel** > **Automation**
2. Verify your automation rule is listed and enabled
3. The rule should show the Logic App as the playbook action

### Test Alert Forwarding

Trigger a test alert in Sentinel to verify the full pipeline:

1. Create or wait for a Sentinel analytic rule to fire
2. An incident will be created in Sentinel
3. The automation rule triggers the Logic App
4. Check the Logic App **Run history** in the Azure Portal
5. A successful run shows status "Succeeded" with a 200 response from the Tuskira API

### Check Logic App Run History

1. Open the Logic App in Azure Portal
2. Click **Run history** in the Overview pane
3. Each run shows:
   - **Status**: Succeeded / Failed
   - **Trigger**: Microsoft_Sentinel_incident
   - **Duration**: Typically 2-5 seconds

Click on a run to see the detailed execution of each step.

---

## 6. Updating Credentials

If you need to rotate your Tuskira API key:

1. Update the `api_key` value in your `terraform.tfvars`
2. Run `terraform apply`
3. The new key is stored in Key Vault and used by the Logic App on the next run

No restart or redeployment of the Logic App is needed.

---

## 7. Troubleshooting

### "Missing required permissions for Microsoft Sentinel on the playbook"

**Cause**: The Azure Security Insights service principal does not have the Sentinel Automation Contributor role on the Logic App.

**Fix**: Run `terraform apply` again. The module automatically creates this role assignment. If it persists, verify your deployer has `User Access Administrator` on the resource group.

### "Forbidden" errors in Logic App run history

**Cause**: The Logic App's managed identity does not have the correct roles.

**Fix**: Verify the `Microsoft Sentinel Responder` role exists on the workspace:

```bash
az role assignment list \
  --scope "/subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.OperationalInsights/workspaces/WORKSPACE" \
  --query "[?roleDefinitionName=='Microsoft Sentinel Responder']" \
  -o table
```

If missing, run `terraform apply` to recreate it.

### Logic App runs are not being triggered

**Cause**: No automation rule is connecting the analytic rule to the Logic App.

**Fix**:
- If using Portal UI: Check Sentinel > Automation for your rule
- If using Terraform: Verify `enable_automation_rules = true` and `alert_rule_ids` contains the correct rule IDs
- Verify the analytic rule is enabled and creating incidents

### Key Vault access denied

**Cause**: The Logic App's managed identity lost its Key Vault access policy.

**Fix**: Run `terraform apply` to recreate the access policy.

### "Directory.Read.All" or service principal lookup fails

**Cause**: The deployer does not have Azure AD read permissions.

**Fix**: Ask your Azure AD administrator to assign the **Directory Readers** role:

```bash
az ad signed-in-user show --query id -o tsv
# Give this object ID to your admin to add to Directory Readers role
```

---

## 8. Uninstalling

To remove all deployed resources:

```bash
terraform destroy
```

This removes the Logic App, Key Vault, managed identity, connections, role assignments, and automation rules. It does **not** affect your Sentinel workspace, analytic rules, or existing incidents.

---

## Support

For questions about this deployment, contact your Tuskira representative or email support@tuskira.ai.
