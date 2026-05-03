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

# Note: OpenAI variables removed because Azure OpenAI deployment is omitted
# from this stack (subscription has 0 OpenAI quota). Narrative falls back to
# template summary. To re-enable OpenAI, restore the openai_* variables and
# the openai.tf resource file, then set OPENAI_ENDPOINT/OPENAI_DEPLOYMENT
# env vars on the Container App Job.

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
