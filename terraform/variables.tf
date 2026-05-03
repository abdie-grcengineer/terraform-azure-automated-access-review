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

# Azure OpenAI deployment name (this is the name we create on the OpenAI account;
# the application code passes it as the "model" parameter).
variable "openai_deployment_name" {
  description = "Azure OpenAI deployment name"
  type        = string
  default     = "gpt-4-1-mini"
}

# Underlying OpenAI model. gpt-4.1-mini is GA and right-sized for summarization.
# (gpt-4o-mini 2024-07-18 was deprecated 03/31/2026 in some regions.)
variable "openai_model_name" {
  description = "Underlying Azure OpenAI model"
  type        = string
  default     = "gpt-4.1-mini"
}

variable "openai_model_version" {
  description = "Version of the underlying OpenAI model"
  type        = string
  default     = "2025-04-14"
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
