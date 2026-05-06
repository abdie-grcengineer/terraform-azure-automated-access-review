# Input variables for the Azure Automated Access Review stack.
# Required variables (no default) must be supplied via terraform.tfvars
# or via TF_VAR_<name> environment variables (which is how CI passes secrets).

variable "subscription_id" {
  description = "Azure subscription ID where all resources will be created"
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra ID tenant ID"
  type        = string
}

variable "recipient_email" {
  description = "Email address that receives the access review report"
  type        = string
}

# Default Azure location.
# eastus2 is the default because Container Apps and Azure OpenAI are both
# available with default quota allocations on new subscriptions.
variable "location" {
  description = "Azure location (region) for resources"
  type        = string
  default     = "eastus2"
}

# Standard cron schedule for the Container App Job.
# Container Apps Jobs use standard 5-field cron (no seconds field).
# "0 8 1 * *" = at 08:00 on the 1st of every month.
variable "schedule_cron" {
  description = "Cron expression for the Container App Job schedule"
  type        = string
  default     = "0 8 1 * *"
}

# Microsoft Foundry (formerly Azure AI Services) model deployment for the
# executive narrative summary. Defaults target Phi-4-mini-instruct, a
# Microsoft-trained model sold directly by Azure (no Marketplace subscription
# required, no third-party model provenance to defend in audit).
#
# How these three variables fit together: they describe one model deployment.
# In Cognitive Services / Foundry, a "deployment" is a named instance of a
# specific model version running on an account. Three pieces describe it:
#
#   foundry_deployment_name  -> a name we choose; what the application sends
#                               as "model" in the chat completions request
#   foundry_model_name       -> what the model is called in Microsoft's catalog
#   foundry_model_version    -> which version of that model
#
# One Foundry resource can host multiple deployments. You could have one
# deployment running Phi-4-mini-instruct version 1 with default content
# filtering, and a second deployment of the same model with a stricter
# content filter, accessible under a different name.
#
# How to switch models: look up replacement values with
#   az cognitiveservices account list-models -n <foundry-name> -g <rg>
# and update format, name, and version. The deployment name is just a label;
# you can keep "Phi-4-mini-instruct" or change it.
#
# How to revert to Azure OpenAI when quota becomes available: this stack
# previously used Azure OpenAI before pivoting to Foundry. The pre-pivot
# Terraform is in git history at commit 357a8b7^.

# The deployment name. Used by:
# - terraform/foundry.tf (azurerm_cognitive_deployment.phi.name)
# - terraform/function.tf (FOUNDRY_DEPLOYMENT env var on the job)
# - the application code (sent as "model" in chat completions)
variable "foundry_deployment_name" {
  description = "Name of the model deployment created on the Foundry resource. Sent as the 'model' field in chat completions calls."
  type        = string
  default     = "Phi-4-mini-instruct"
}

# Underlying Microsoft-published model. Must match the catalog name exactly.
# For Phi family this is "Phi-4-mini-instruct" (or "Phi-4", "Phi-4-multimodal-instruct", etc.).
variable "foundry_model_name" {
  description = "Underlying model published by Microsoft. Must match the catalog name."
  type        = string
  default     = "Phi-4-mini-instruct"
}

# Model version. Microsoft uses simple integer versions for Phi, dated
# versions for some other models (e.g., gpt-4o-mini "2024-07-18").
# The list-models command shows current valid versions.
variable "foundry_model_version" {
  description = "Version of the Foundry model. Per Microsoft's catalog the GA version of Phi-4-mini-instruct is '1'."
  type        = string
  default     = "1"
}

# Used to prefix all resource names so they are identifiable in the Azure console.
variable "name_prefix" {
  description = "Prefix applied to resource names"
  type        = string
  default     = "azure-access-review"
}

variable "report_retention_days" {
  description = "Number of days to retain CSV reports before lifecycle deletes them"
  type        = number
  default     = 90
}
