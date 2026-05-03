# Identity model for the function and its role assignments.
#
# Azure RBAC notes:
# - You assign a principal (user, group, service principal, managed identity)
#   to a built-in or custom role at a scope (mgmt group, subscription, resource
#   group, individual resource).
# - The "policy" on a resource is the union of all role assignments at all
#   enclosing scopes.
# - Use built-in roles when possible; custom roles introduce maintenance burden.
#
# The Function App in function.tf creates a system-assigned managed identity
# automatically (because we set identity { type = "SystemAssigned" }).
# Role assignments below grant that identity the permissions the function needs.
#
# NOTE: We reference azurerm_linux_function_app.access_review.identity[0].principal_id
# from function.tf for the managed identity's principal ID.

# Permission: read role assignments at subscription scope.
# Reader gets us most of what we need for an access review (list resources,
# read RBAC, view diagnostic settings). It's a built-in broad-read role.
resource "azurerm_role_assignment" "function_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_function_app.access_review.identity[0].principal_id
}

# Permission: read Defender for Cloud findings (alerts, recommendations).
# Security Reader is the read-only role for security data.
resource "azurerm_role_assignment" "function_security_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Security Reader"
  principal_id         = azurerm_linux_function_app.access_review.identity[0].principal_id
}

# Permission: read Activity Log (Azure's equivalent of an audit log).
# Monitoring Reader includes log read.
resource "azurerm_role_assignment" "function_monitoring_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_linux_function_app.access_review.identity[0].principal_id
}

# Permission: write blobs to the report storage account.
# Bucket-scoped binding: function only writes to this specific storage account,
# not all storage accounts in the subscription. Least privilege.
resource "azurerm_role_assignment" "function_storage_writer" {
  scope                = azurerm_storage_account.report.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.access_review.identity[0].principal_id
}

# Permission: invoke Azure OpenAI models.
# Cognitive Services OpenAI User is the read-execute role for OpenAI.
resource "azurerm_role_assignment" "function_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.access_review.identity[0].principal_id
}
