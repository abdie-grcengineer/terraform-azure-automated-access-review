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

# Build and push the container image to ACR using `az acr build`.
# This runs locally on the machine running terraform (CI runner or your laptop).
# az acr build sends the source to ACR and builds remotely; no local Docker required.
# The triggers map ensures we only rebuild when source files change.
resource "terraform_data" "image_build" {
  triggers_replace = {
    dockerfile = filemd5("${path.module}/../src/function/Dockerfile")
    main_py    = filemd5("${path.module}/../src/function/main.py")
    # Hash of all Python files in src/function: triggers a rebuild on any change.
    src_hash = sha256(join("", [for f in fileset("${path.module}/../src/function", "**/*.py") : filemd5("${path.module}/../src/function/${f}")]))
  }

  provisioner "local-exec" {
    # Run from the source dir so 'Dockerfile' resolves correctly without
    # needing an absolute --file path.
    working_dir = "${path.module}/../src/function"
    command     = <<-EOT
      az acr build \
        --registry ${azurerm_container_registry.main.name} \
        --image access-review:latest \
        --image access-review:${substr(self.triggers_replace.src_hash, 0, 12)} \
        .
    EOT
  }

  depends_on = [azurerm_container_registry.main]
}

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
      # OPENAI_ENDPOINT and OPENAI_DEPLOYMENT are intentionally empty.
      # The narrative module checks for these and falls back to a template
      # summary when missing. Subscription-level OpenAI quota is 0 across all
      # GA models in the available regions; rather than block the deploy, we
      # use the graceful-fallback path the code was designed for.
      env {
        name  = "OPENAI_ENDPOINT"
        value = ""
      }
      env {
        name  = "OPENAI_DEPLOYMENT"
        value = ""
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
    terraform_data.image_build,
  ]
}
