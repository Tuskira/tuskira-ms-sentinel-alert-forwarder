terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.12"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "azapi" {}
provider "azuread" {}

# -----------------------------------------------------------------------------
# Variables — set these in a .tfvars file or via environment variables
# -----------------------------------------------------------------------------

variable "tenant_name" {
  description = "Short name for your tenant (used in resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "australiaeast"
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace with Sentinel enabled"
  type        = string
}

variable "api_url" {
  description = "Tuskira API endpoint (e.g. https://<tenant>.tuskira.ai/api/v2/alerts)"
  type        = string
}

variable "api_key" {
  description = "Tuskira API Bearer token"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Module
# -----------------------------------------------------------------------------

module "sentinel_forwarder" {
  source = "../../"

  tenant_name                = var.tenant_name
  environment                = var.environment
  resource_group_name        = var.resource_group_name
  location                   = var.location
  log_analytics_workspace_id = var.log_analytics_workspace_id
  api_url                    = var.api_url
  api_key                    = var.api_key

  # Optional: create automation rules via Terraform for specific analytic rules.
  # If false (default), attach the playbook manually via the Sentinel Portal UI.
  # enable_automation_rules = true
  # alert_rule_ids = [
  #   "/subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.OperationalInsights/workspaces/WS/providers/Microsoft.SecurityInsights/alertRules/RULE_NAME",
  # ]

  tags = {
    managed_by  = "terraform"
    component   = "sentinel-alert-forwarder"
    environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "logic_app_id" {
  description = "Resource ID of the deployed Logic App"
  value       = module.sentinel_forwarder.logic_app_id
}

output "logic_app_name" {
  description = "Name of the Logic App (use this to find it in the Sentinel Playbooks list)"
  value       = module.sentinel_forwarder.logic_app_name
}

output "managed_identity_principal_id" {
  description = "Principal ID of the Logic App managed identity — grant it Microsoft Sentinel Responder role"
  value       = module.sentinel_forwarder.managed_identity_principal_id
}
