variable "name" {
  description = "Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "A vault name has 3 to 24 characters, starts with a letter, ends with a letter or digit and holds only letters, digits and hyphens."
  }
}

variable "resource_group_name" {
  description = "Resource group that holds the vault."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "log_analytics_workspace_id" {
  description = "Workspace that receives the AuditEvent log."
  type        = string
}

variable "soft_delete_retention_days" {
  description = "Days a deleted vault keeps its name reserved. The minimum, 7, keeps practice runs short."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  description = "When true, a deleted vault cannot be purged until the retention ends. Turn it on in production; leave it off for practice so the name can be reused."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Public endpoint on or off. This project keeps it on; the private platform slice project turns it off behind a private endpoint."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the vault."
  type        = map(string)
  default     = {}
}
