output "name" {
  description = "Container app name."
  value       = azurerm_container_app.this.name
}

output "fqdn" {
  description = "Public host name of the app."
  value       = azurerm_container_app.this.ingress[0].fqdn
}

output "url" {
  description = "HTTPS address of the app."
  value       = "https://${azurerm_container_app.this.ingress[0].fqdn}"
}
