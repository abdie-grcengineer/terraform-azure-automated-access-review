# Input variables for the Azure Automated Access Review stack.
# Required variables (no default) must be supplied via terraform.tfvars
# or via TF_VAR_<name> environment variables (which is how CI passes secrets).

# The Azure subscription ID where everything gets deployed.
# In Azure, every resource lives in exactly one subscription; the subscription
# is the resource container and billing boundary.
variable "subscription_id" {
  description = "Azure subscription ID where all resources will be created"
  type        = string
}

# The Azure tenant ID (Microsoft Entra ID directory).
# A tenant can host many subscriptions; the tenant ID is required by some
# Azure services (Key Vault, OpenAI) for identity federation.
variable "tenant_id" {
  description = "Microsoft Entra ID tenant ID"
  type        = string
}

# The recipient email for the report.
# In CI, this comes from the RECIPIENT_EMAIL GitHub secret via TF_VAR_recipient_email.
# Locally, set it in terraform.tfvars (which is gitignored).
variable "recipient_email" {
  description = "Email address that receives the access review report"
  type        = string
}

# Default Azure location (region) for resources.
# eastus is chosen because Azure OpenAI and Communication Services Email are
# both available there. Many Azure features are region-gated; eastus is the
# most feature-complete region in the US.
variable "location" {
  description = "Azure location (region) for resources"
  type        = string
  default     = "eastus"
}

# NCRONTAB schedule for the Timer trigger.
# Format: {second} {minute} {hour} {day} {month} {day-of-week}.
# "0 0 8 1 * *" = 08:00:00 on the 1st of every month, any day-of-week.
# This is Azure Functions' specific cron format (6 fields, includes seconds).
variable "schedule_ncrontab" {
  description = "NCRONTAB expression for the Timer trigger schedule"
  type        = string
  default     = "0 0 8 1 * *"
}

# Azure OpenAI model deployment name.
# This is the deployment name we create on the OpenAI resource; the function
# code passes this string to the OpenAI client as the model parameter.
variable "openai_deployment_name" {
  description = "Azure OpenAI deployment name (must match azurerm_cognitive_deployment.gpt name)"
  type        = string
  default     = "gpt-4o-mini"
}

# The underlying OpenAI model the deployment uses.
# gpt-4o-mini is the cost-and-speed-optimized tier; right-sized for summarization.
# Larger models would be 5-10x the cost for marginal quality lift on this workload.
variable "openai_model_name" {
  description = "Underlying Azure OpenAI model"
  type        = string
  default     = "gpt-4o-mini"
}

variable "openai_model_version" {
  description = "Version of the underlying OpenAI model"
  type        = string
  default     = "2024-07-18"
}

# Used to prefix all resource names so they're identifiable in the Azure console.
variable "name_prefix" {
  description = "Prefix applied to resource names"
  type        = string
  default     = "azure-access-review"
}

# Force-destroy the report storage on terraform destroy even with blobs present.
# Set to true for the demo so 'terraform destroy' works without manual cleanup.
# In production this should be false; you don't want destroy to delete audit evidence.
variable "report_storage_force_destroy" {
  description = "Allow terraform destroy to delete the report storage even if non-empty"
  type        = bool
  default     = true
}

variable "report_retention_days" {
  description = "Number of days to retain CSV reports before lifecycle deletes them"
  type        = number
  default     = 90
}
