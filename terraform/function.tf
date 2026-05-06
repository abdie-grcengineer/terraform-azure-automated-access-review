# Container App Job (compute) and its supporting infrastructure.
#
# Pivoted from Azure Functions Consumption plan because new subscriptions have
# zero default quota for Functions Consumption (Dynamic VMs). Container Apps
# uses a different quota pool that has default capacity even on new subs.
# The architecture is still serverless: the job scales to zero between runs,
# pay-per-execution.
#
# Components:
# 1. Azure Container Registry (ACR): hosts the container image we run.
# 2. Container App Environment: the managed Kubernetes-like host for jobs.
# 3. Container App Job: the actual scheduled job, with a cron trigger.
# 4. User-assigned managed identity: the job's identity for Azure auth.

# Container Registry to host the job image.
# Basic SKU is the cheapest tier; sufficient for a single-image, low-volume job.
resource "azurerm_container_registry" "main" {
  name                = substr(replace("${var.name_prefix}acr${random_string.suffix.result}", "-", ""), 0, 50)
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false # Use Entra ID auth instead of admin user
  tags                = local.common_tags
}

# Log Analytics workspace for Container Apps logs.
# Container Apps requires a Log Analytics workspace to send logs to.
# Reused for Application Insights elsewhere in this module.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# Container App Environment: the managed host that runs container apps and jobs.
# All jobs in a project typically share one environment.
resource "azurerm_container_app_environment" "main" {
  name                       = "${var.name_prefix}-cae"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.common_tags
}

# User-assigned managed identity for the job.
# We use user-assigned (rather than system-assigned) so the identity exists
# before the job is created, which lets us grant ACR pull access to the
# identity before the job tries to pull the image.
resource "azurerm_user_assigned_identity" "job" {
  name                = "${var.name_prefix}-job-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags
}

# Grant the job's identity pull access to ACR.
# Required so the job can fetch its container image at start time.
resource "azurerm_role_assignment" "job_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# Image build is decoupled from Terraform.
#
# Why decoupled: Terraform used to run `az acr build` via local-exec, which
# requires ACR Tasks. ACR Tasks is gated at the subscription level on some
# Azure tiers and was blocked on this sub. More importantly, building artifacts
# inside Terraform conflates two concerns that production systems keep separate:
# CI builds the artifact (the container image), CD applies the infrastructure.
#
# Where the image gets built now: GitHub Actions runs `az acr login` + docker
# build + docker push as a step BEFORE `terraform apply`. The runner has Docker
# preinstalled, no ACR Tasks dependency. See .github/workflows/terraform.yml.
#
# What Terraform expects: an image tagged `:latest` already present in ACR
# at the time of apply. The Container App Job below references it directly.
# If you're applying locally for development, push an image first via the same
# pattern (az acr login + docker build + docker push) before running apply.

# Container App Job: the scheduled access review.
# trigger_type = "Schedule" makes this a recurring job on a cron schedule.
# Other trigger types: "Manual" (run on demand) and "Event" (event-driven).
resource "azurerm_container_app_job" "access_review" {
  name                         = "${var.name_prefix}-job"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id

  replica_timeout_in_seconds = 1800 # 30 minutes max per execution
  replica_retry_limit        = 1

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.job.id]
  }

  # Tell Container Apps to use the user-assigned identity to pull from ACR.
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.job.id
  }

  # Schedule trigger config (NCRONTAB-style standard cron, 5 fields, no seconds).
  schedule_trigger_config {
    cron_expression          = var.schedule_cron
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name = "access-review"
      # Image: the ACR-hosted image. The image tag is "latest"; CI builds and
      # pushes a new "latest" before each terraform apply.
      image = "${azurerm_container_registry.main.login_server}/access-review:latest"

      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "SUBSCRIPTION_ID"
        value = var.subscription_id
      }
      env {
        name  = "REPORT_STORAGE_ACCOUNT"
        value = azurerm_storage_account.report.name
      }
      env {
        name  = "REPORT_CONTAINER"
        value = azurerm_storage_container.reports.name
      }
      env {
        name  = "RECIPIENT_EMAIL"
        value = var.recipient_email
      }
      # Foundry inference configuration.
      #
      # The narrative module in src/function/narrative.py reads these two
      # env vars and uses them to call the v1 OpenAI-compatible chat
      # completions endpoint on our Foundry resource. Two values are needed
      # because Foundry separates "where to send the request" from "which
      # model deployment should handle it":
      #
      # FOUNDRY_ENDPOINT
      #   The hostname of the Foundry resource. Set in foundry.tf via the
      #   local.foundry_endpoint expression. Format:
      #     https://<custom-subdomain>.openai.azure.com
      #   The function code appends "/openai/v1/" itself when constructing
      #   the OpenAI client base URL.
      #
      # FOUNDRY_DEPLOYMENT
      #   The name of the model deployment created on the Foundry resource.
      #   This is what the function sends as the "model" field in the chat
      #   completions request body. One Foundry resource can host multiple
      #   deployments (different models, different versions, or the same
      #   model with different content filter policies); the deployment name
      #   selects which one handles the request.
      env {
        name  = "FOUNDRY_ENDPOINT"
        value = local.foundry_endpoint
      }
      env {
        name  = "FOUNDRY_DEPLOYMENT"
        value = azurerm_cognitive_deployment.phi.name
      }
      env {
        name  = "ACS_ENDPOINT"
        value = "https://${azurerm_communication_service.main.name}.communication.azure.com"
      }
      env {
        name  = "ACS_SENDER_ADDRESS"
        value = "donotreply@${azurerm_email_communication_service_domain.main.from_sender_domain}"
      }
      # AZURE_CLIENT_ID tells DefaultAzureCredential which managed identity
      # to use when there are multiple options. Required for user-assigned MI
      # in Container Apps.
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.job.client_id
      }
    }
  }

  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.job_acr_pull,
  ]
}
