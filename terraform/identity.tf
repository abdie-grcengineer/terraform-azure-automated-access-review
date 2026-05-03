# Role assignments for the Container App Job's user-assigned managed identity.
#
# Azure RBAC notes:
# - You assign a principal (user, group, service principal, managed identity)
#   to a built-in or custom role at a scope (mgmt group, subscription, resource
#   group, individual resource).
# - The "policy" on a resource is the union of all role assignments at all
#   enclosing scopes.
# - Use built-in roles when possible; custom roles introduce maintenance burden.
#
# The user-assigned identity itself is created in function.tf
# (azurerm_user_assigned_identity.job). Role assignments below grant that
# identity the permissions the job needs to do its work.

# Permission: read the project's IAM policy and resource inventory.
# Reader gets us most of what we need for an access review.
resource "azurerm_role_assignment" "job_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# Permission: read Defender for Cloud findings (alerts, recommendations).
resource "azurerm_role_assignment" "job_security_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Security Reader"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# Permission: read Activity Log entries.
resource "azurerm_role_assignment" "job_monitoring_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# Permission: write blobs to the report storage account.
resource "azurerm_role_assignment" "job_storage_writer" {
  scope                = azurerm_storage_account.report.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# Note: OpenAI role assignment removed because Azure OpenAI deployment is
# omitted from this stack (subscription has 0 OpenAI quota across all GA
# models in the available regions). The function's narrative module gracefully
# falls back to a template summary when no AI endpoint is configured.
