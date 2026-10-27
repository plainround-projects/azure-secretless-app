output "resource_group_name" {
  description = "The one resource group; deleting it is the clean-up plan."
  value       = azurerm_resource_group.this.name
}

output "key_vault_name" {
  description = "Vault name (for `az keyvault secret set --vault-name`)."
  value       = module.key_vault.name
}

output "vault_url" {
  description = "The app's VAULT_URL."
  value       = module.key_vault.vault_uri
}

output "storage_account_name" {
  description = "Account name (for `az storage blob list --account-name`)."
  value       = module.storage.name
}

output "storage_url" {
  description = "The app's STORAGE_URL."
  value       = module.storage.blob_endpoint
}

output "container_name" {
  description = "The uploads container."
  value       = module.storage.container_name
}

output "registry_name" {
  description = "Registry name for `az acr build`."
  value       = module.registry.name
}

output "registry_login_server" {
  description = "Registry host, the prefix of the image name."
  value       = module.registry.login_server
}

output "app_identity_name" {
  description = "Name of the identity the app runs as."
  value       = module.app_identity.name
}

output "app_identity_client_id" {
  description = "The app's AZURE_CLIENT_ID. It names the identity and is not a secret."
  value       = module.app_identity.client_id
}

output "app_identity_principal_id" {
  description = "Object id of the app identity; the 403 messages in the logs show this value."
  value       = module.app_identity.principal_id
}

output "log_analytics_workspace_name" {
  description = "Workspace name."
  value       = module.log_analytics.name
}

output "log_analytics_customer_id" {
  description = "Workspace customer id for `az monitor log-analytics query --workspace`."
  value       = module.log_analytics.workspace_id
}

output "app_name" {
  description = "Container app name, or null until deploy_app is true."
  value       = one(module.container_app[*].name)
}

output "app_url" {
  description = "HTTPS address of the app, or null until deploy_app is true."
  value       = one(module.container_app[*].url)
}

output "app_role_assignments" {
  description = "The app identity's role assignments. The lesson's Done when: exactly two, each on a single resource."
  value = [
    for assignment in module.role_assignments.assignments :
    { role = assignment.role, scope = assignment.scope }
    if assignment.principal_id == module.app_identity.principal_id
  ]
}
