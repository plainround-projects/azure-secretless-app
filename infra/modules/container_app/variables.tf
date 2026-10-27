variable "name" {
  description = "Container app name."
  type        = string
}

variable "environment_name" {
  description = "Container Apps environment name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds both."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace that receives the console logs."
  type        = string
}

variable "image" {
  description = "Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag or a digest, never latest."
  type        = string

  validation {
    condition     = !endswith(var.image, ":latest") && can(regex(":[^/]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry a version tag or a digest, and not be :latest."
  }
}

variable "container_port" {
  description = "Port the app listens on."
  type        = number
  default     = 8000
}

variable "app_identity_id" {
  description = "Resource id of the identity the app runs as (it holds the two data roles)."
  type        = string
}

variable "pull_identity_id" {
  description = "Resource id of the identity that only pulls the image (AcrPull on the registry)."
  type        = string
}

variable "registry_server" {
  description = "Registry host, for example myregistry.azurecr.io."
  type        = string
}

variable "env" {
  description = "Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value."
  type        = map(string)
  default     = {}

  validation {
    condition = !anytrue([
      for name in keys(var.env) :
      can(regex("(?i)(password|passwd|connection_?string|client_?secret|account_?key|sas_?token|api_?key)", name))
    ])
    error_message = "An environment variable name suggests a credential (password, connection string, client secret, account key, SAS token, API key). The app authenticates with its managed identity instead."
  }

  validation {
    condition = !anytrue([
      for value in values(var.env) :
      can(regex("(?i)(accountkey=|sharedaccesssignature=|[?&]sig=|password=|pwd=|-----BEGIN)", value))
    ])
    error_message = "An environment variable value looks like a connection string, SAS token or private key."
  }
}

variable "min_replicas" {
  description = "Minimum replicas. 0 scales to zero and costs nothing idle but adds a cold start."
  type        = number
  default     = 0

  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= var.max_replicas
    error_message = "min_replicas must be between 0 and max_replicas."
  }
}

variable "max_replicas" {
  description = "Maximum replicas."
  type        = number
  default     = 2
}

variable "cpu" {
  description = "vCPU per replica."
  type        = number
  default     = 0.25
}

variable "memory" {
  description = "Memory per replica; Container Apps pairs 0.25 vCPU with 0.5Gi."
  type        = string
  default     = "0.5Gi"
}

variable "tags" {
  description = "Tags applied to both resources."
  type        = map(string)
  default     = {}
}
