provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # scripts/provision.sh registers the resource providers this slice needs, so the plan never changes
  # subscription-wide settings on its own.
  resource_provider_registrations = "none"

  features {
    key_vault {
      # A destroyed vault stays soft-deleted for its retention period (step 6 of the lesson looks at this).
      # purge_soft_delete_on_destroy = true would purge it at once, which purge protection forbids anyway.
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
