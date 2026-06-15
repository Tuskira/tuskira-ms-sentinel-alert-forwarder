variable "resource_group_name" {
  description = "Name of the resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "australiaeast"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tenant_name" {
  description = "Short name for the MSSP tenant (used in resource naming)"
  type        = string
}

# --- Tuskira API ---

variable "api_url" {
  description = "Tuskira API endpoint URL (e.g. https://customer.tuskira.ai/api/v2/alerts)"
  type        = string
}

variable "api_key" {
  description = "Tuskira API Bearer token"
  type        = string
  sensitive   = true
}

# --- Sentinel Workspace ---

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (/subscriptions/.../workspaces/...)"
  type        = string
}

# --- Automation Rules ---

variable "enable_automation_rules" {
  description = "Create automation rules via Terraform. If false, attach playbook via Sentinel Portal UI."
  type        = bool
  default     = false
}

variable "alert_rule_ids" {
  description = "Analytic rule IDs to attach the playbook to (only used when enable_automation_rules = true)"
  type        = list(string)
  default     = []
}

# --- Tags ---

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "tuskira-terraform"
    component  = "tuskira-sentinel-alert-forwarder"
  }
}
