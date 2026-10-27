output "id" {
  description = "Account resource id."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Account name."
  value       = azurerm_storage_account.this.name
}

output "blob_endpoint" {
  description = "Blob address; the app's STORAGE_URL. An address, not a secret."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_name" {
  description = "Name of the uploads container."
  value       = azurerm_storage_container.uploads.name
}

output "container_resource_manager_id" {
  description = "Resource id of the container (.../blobServices/default/containers/uploads): the narrowest scope for the blob role."
  value       = azurerm_storage_container.uploads.id
}
