output "id" {
  description = "Resource id; the narrowest scope for the Key Vault Secrets User role."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Vault name."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Vault address; the app's VAULT_URL. An address, not a secret."
  value       = azurerm_key_vault.this.vault_uri
}
