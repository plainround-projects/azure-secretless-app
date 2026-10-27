variable "subscription_id" {
  description = "Subscription GUID (`az account show --query id`)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "tenant_id" {
  description = "Entra tenant GUID (`az account show --query tenantId`)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "Environment name, used in tags."
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else."
  type        = string
  default     = "secretless"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 12 lowercase letters or digits."
  }
}

variable "suffix" {
  description = "Five lowercase characters that make the vault, storage and registry names globally unique. Leave null to generate one."
  type        = string
  default     = null

  validation {
    condition     = var.suffix == null || can(regex("^[a-z0-9]{3,6}$", var.suffix))
    error_message = "suffix must be 3 to 6 lowercase letters or digits."
  }
}

variable "deployer_object_id" {
  description = "Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get Key Vault Secrets Officer on the vault and Storage Blob Data Reader on the container, so they can set the secret and list blobs. Null grants nothing."
  type        = string
  default     = null
}

variable "purge_protection_enabled" {
  description = "Vault purge protection. False for practice (the name can be purged and reused); true in production."
  type        = bool
  default     = false
}

variable "deploy_app" {
  description = "False creates everything except the container app, so the image can be built in the registry first. True adds the app (set `image`)."
  type        = bool
  default     = false
}

variable "image" {
  description = "Image for the container app, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Required when deploy_app is true."
  type        = string
  default     = null

  validation {
    condition     = !var.deploy_app || var.image != null
    error_message = "Set image when deploy_app is true."
  }
}

variable "budget_contact_emails" {
  description = "Recipients of the budget alerts. An empty list creates no budget."
  type        = list(string)
  default     = []
}

variable "budget_amount" {
  description = "Monthly budget in the billing currency."
  type        = number
  default     = 20
}

variable "budget_start_date" {
  description = "First of a month at midnight UTC, for example 2026-11-01T00:00:00Z. Required when budget_contact_emails is set."
  type        = string
  default     = null

  validation {
    condition     = length(var.budget_contact_emails) == 0 || var.budget_start_date != null
    error_message = "Set budget_start_date when budget_contact_emails is set."
  }
}

variable "tags" {
  description = "Extra tags merged into the standard ones."
  type        = map(string)
  default     = {}
}
