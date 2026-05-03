# Outputs make Terraform's resource attributes available after apply.
# Queried with `terraform output -raw NAME` and used by the bash scripts
# to find the resources they need to interact with.

output "resource_group" {
  description = "Resource group containing all access review resources"
  value       = azurerm_resource_group.main.name
}

output "container_app_job_name" {
  description = "Name of the Container App Job (use to invoke or query manually)"
  value       = azurerm_container_app_job.access_review.name
}

output "container_registry" {
  description = "Container Registry hosting the job image"
  value       = azurerm_container_registry.main.login_server
}

output "report_storage_account" {
  description = "Storage account holding access review CSV reports"
  value       = azurerm_storage_account.report.name
}

output "report_container" {
  description = "Container inside the report storage account where CSVs land"
  value       = azurerm_storage_container.reports.name
}

output "acs_endpoint" {
  description = "Azure Communication Services endpoint URL"
  value       = "https://${azurerm_communication_service.main.name}.communication.azure.com"
}

output "acs_sender_address" {
  description = "Sender email address (Azure-managed domain)"
  value       = "donotreply@${azurerm_email_communication_service_domain.main.from_sender_domain}"
}

output "job_principal_id" {
  description = "Object ID of the job's managed identity (for IAM debugging)"
  value       = azurerm_user_assigned_identity.job.principal_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = var.subscription_id
}

output "location" {
  description = "Azure region where regional resources live"
  value       = var.location
}
