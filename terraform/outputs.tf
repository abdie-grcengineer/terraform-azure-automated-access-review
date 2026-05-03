# Outputs make Terraform's resource attributes available after apply.
# Queried with `terraform output -raw NAME` and used by the bash scripts
# to find the resources they need to interact with.

output "resource_group" {
  description = "Resource group containing all access review resources"
  value       = azurerm_resource_group.main.name
}

output "function_name" {
  description = "Name of the Function App (use to invoke or query manually)"
  value       = azurerm_linux_function_app.access_review.name
}

output "function_default_hostname" {
  description = "Default hostname of the Function App (HTTPS)"
  value       = azurerm_linux_function_app.access_review.default_hostname
}

output "report_storage_account" {
  description = "Storage account holding access review CSV reports"
  value       = azurerm_storage_account.report.name
}

output "report_container" {
  description = "Container inside the report storage account where CSVs land"
  value       = azurerm_storage_container.reports.name
}

output "openai_endpoint" {
  description = "Azure OpenAI service endpoint URL"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_deployment" {
  description = "Azure OpenAI deployment name (passed to the OpenAI client as 'model')"
  value       = azurerm_cognitive_deployment.gpt.name
}

output "acs_endpoint" {
  description = "Azure Communication Services endpoint URL"
  value       = "https://${azurerm_communication_service.main.name}.communication.azure.com"
}

output "acs_sender_address" {
  description = "Sender email address (Azure-managed domain)"
  value       = "donotreply@${azurerm_email_communication_service_domain.main.from_sender_domain}"
}

output "function_principal_id" {
  description = "Object ID of the Function App's managed identity (for IAM debugging)"
  value       = azurerm_linux_function_app.access_review.identity[0].principal_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = var.subscription_id
}

output "location" {
  description = "Azure region where regional resources live"
  value       = var.location
}
