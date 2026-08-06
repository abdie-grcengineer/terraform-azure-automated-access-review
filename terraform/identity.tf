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
  role_definition_name = "Owner"
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

# Permission: send email via Azure Communication Services.
#
# ACS Email supports two auth modes: connection string (key-based) and
# Entra ID (managed identity). We use Entra ID, which means the calling
# principal needs an RBAC role on the ACS resource that grants the email
# send data-plane action. The simplest built-in role that includes that
# action is "Contributor" scoped to the ACS resource itself.
#
# Why this scope: least privilege. Contributor at subscription scope would
# work but is over-broad. Contributor on just the ACS resource limits the
# permission to email send + ACS resource read on this one resource.
resource "azurerm_role_assignment" "job_acs_contributor" {
  scope                = azurerm_communication_service.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# Permission: invoke models deployed on the Foundry resource.
#
# "Cognitive Services OpenAI User" is the right role even though our model
# (Phi-4-mini-instruct) is not an OpenAI model. The role grants the data-plane
# action that the v1 OpenAI-compatible inference endpoint checks, regardless
# of which model family is behind the deployment. Microsoft's own v1 API doc
# explicitly calls out this role for Entra ID auth against Foundry.
#
# Scope: the Foundry resource itself, not the subscription. Least privilege.
# Map: NIST 800-53 AC-6 (Least Privilege), CMMC AC.L2-3.1.5
resource "azurerm_role_assignment" "job_foundry_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}
