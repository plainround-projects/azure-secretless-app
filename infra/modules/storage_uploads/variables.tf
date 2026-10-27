variable "name" {
  description = "Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "A storage account name has 3 to 24 lowercase letters and digits and no hyphens."
  }
}

variable "resource_group_name" {
  description = "Resource group that holds the account."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "container_name" {
  description = "The one container the app writes to."
  type        = string
  default     = "uploads"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", var.container_name))
    error_message = "A container name has 3 to 63 lowercase letters, digits and hyphens, without a leading or trailing hyphen."
  }
}

variable "replication_type" {
  description = "LRS keeps three copies in one datacenter: the cheapest, enough for practice."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GRS or GZRS."
  }
}

variable "soft_delete_days" {
  description = "Days deleted blobs and containers can be recovered."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_days >= 1 && var.soft_delete_days <= 365
    error_message = "soft_delete_days must be between 1 and 365."
  }
}

variable "log_analytics_workspace_id" {
  description = "Workspace that receives the blob logs."
  type        = string
}

variable "tags" {
  description = "Tags applied to the account."
  type        = map(string)
  default     = {}
}
