output "endpoint" {
  description = "Set AZURE_OPENAI_ENDPOINT to this."
  value       = azurerm_cognitive_account.this.endpoint
}

output "deployment_name" {
  description = "Set AZURE_OPENAI_DEPLOYMENT to this. Not the model name."
  value       = azurerm_cognitive_deployment.this.name
}

output "resource_id" {
  value = azurerm_cognitive_account.this.id
}

output "identity_principal_id" {
  description = "System-assigned identity of the OpenAI resource itself."
  value       = azurerm_cognitive_account.this.identity[0].principal_id
}

output "key_vault_secret_name" {
  description = "Null when local auth is disabled, which is the intended state."
  value       = local.store_key ? azurerm_key_vault_secret.api_key[0].name : null
}

output "workflow_env" {
  description = "Copy into your workflow env block."
  value = {
    AZURE_OPENAI_ENDPOINT   = azurerm_cognitive_account.this.endpoint
    AZURE_OPENAI_DEPLOYMENT = azurerm_cognitive_deployment.this.name
    AZURE_OPENAI_API_VERSION = "2024-10-21"
  }
}
