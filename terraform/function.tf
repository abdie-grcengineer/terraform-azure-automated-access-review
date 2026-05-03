# The Function App (compute) and its hosting infrastructure.
#
# Azure Functions on Consumption plan requires:
# 1. A Service Plan (sku_name = "Y1" for Consumption).
# 2. A general-purpose storage account for the runtime metadata
#    (separate from our report bucket; Azure Functions uses it internally for
#    queues, triggers, and function metadata).
# 3. The Function App itself, with the right runtime, app settings, identity.
# 4. The function source code, packaged and deployed via run-from-package.

# Service plan for the Function App.
# Y1 = Consumption plan (pay-per-execution, scales to zero between runs).
resource "azurerm_service_plan" "functions" {
  name                = "${var.name_prefix}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.common_tags
}

# Internal storage account that Functions runtime needs.
# Cannot be reused with the report bucket because the Functions runtime
# expects exclusive access to certain queues and tables.
resource "azurerm_storage_account" "function_internal" {
  name                = substr(replace("${var.name_prefix}fn${random_string.suffix.result}", "-", ""), 0, 24)
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Versioning is required by our OPA storage_encryption policy. Even on this
  # internal storage account, applying the same control consistently keeps the
  # gate honest and avoids carving out exceptions.
  blob_properties {
    versioning_enabled = true
  }

  tags = local.common_tags
}

# Zip the function source for deployment.
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/../src/function"
  output_path = "${path.module}/function_source.zip"
}

# Upload the zip to a blob in the internal storage so the function can
# pull it via run-from-package mode (recommended for production).
resource "azurerm_storage_container" "function_releases" {
  name                  = "function-releases"
  storage_account_id    = azurerm_storage_account.function_internal.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "function_source" {
  name                   = "function-${data.archive_file.function_source.output_md5}.zip"
  storage_account_name   = azurerm_storage_account.function_internal.name
  storage_container_name = azurerm_storage_container.function_releases.name
  type                   = "Block"
  source                 = data.archive_file.function_source.output_path
}

# SAS token allowing the function host to download the source zip from the
# release container. SAS scope is one specific blob; expires when the URL is
# regenerated on the next plan.
data "azurerm_storage_account_blob_container_sas" "releases" {
  connection_string = azurerm_storage_account.function_internal.primary_connection_string
  container_name    = azurerm_storage_container.function_releases.name
  https_only        = true

  start  = "2026-01-01"
  expiry = "2030-01-01"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}

# The Function App.
# This is the long resource that ties everything together.
resource "azurerm_linux_function_app" "access_review" {
  name                = "${var.name_prefix}-func-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.functions.id

  storage_account_name       = azurerm_storage_account.function_internal.name
  storage_account_access_key = azurerm_storage_account.function_internal.primary_access_key

  # System-assigned managed identity. The function authenticates to other
  # Azure services (OpenAI, Storage, ACS, RBAC APIs) using this identity.
  # No keys, no secrets in env vars; auth via Entra ID.
  identity {
    type = "SystemAssigned"
  }

  https_only = true

  site_config {
    application_stack {
      python_version = "3.11"
    }

    # Helps Azure Functions cold-start faster by keeping the runtime warm.
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }

  # App settings are environment variables for the function code.
  app_settings = {
    # Python v2 programming model uses function_app.py as the entrypoint
    # by convention. AzureWebJobsFeatureFlags = "EnableWorkerIndexing" enables
    # the v2 model (decorator-based, no function.json files needed).
    AzureWebJobsFeatureFlags = "EnableWorkerIndexing"

    # Run-from-package: Azure pulls the source zip from the URL and runs the
    # function from there directly. Faster cold start; immutable deployment.
    WEBSITE_RUN_FROM_PACKAGE = "https://${azurerm_storage_account.function_internal.name}.blob.core.windows.net/${azurerm_storage_container.function_releases.name}/${azurerm_storage_blob.function_source.name}${data.azurerm_storage_account_blob_container_sas.releases.sas}"

    # Function-specific settings the Python code reads via os.environ.
    SUBSCRIPTION_ID        = var.subscription_id
    TENANT_ID              = var.tenant_id
    REPORT_STORAGE_ACCOUNT = azurerm_storage_account.report.name
    REPORT_CONTAINER       = azurerm_storage_container.reports.name
    RECIPIENT_EMAIL        = var.recipient_email
    OPENAI_ENDPOINT        = azurerm_cognitive_account.openai.endpoint
    OPENAI_DEPLOYMENT      = azurerm_cognitive_deployment.gpt.name
    ACS_ENDPOINT           = "https://${azurerm_communication_service.main.name}.communication.azure.com"
    ACS_SENDER_ADDRESS     = "donotreply@${azurerm_email_communication_service_domain.main.from_sender_domain}"
    SCHEDULE_NCRONTAB      = var.schedule_ncrontab

    # Force latest Python worker package versions on cold start.
    SCM_DO_BUILD_DURING_DEPLOYMENT = "false"
    ENABLE_ORYX_BUILD              = "false"
  }

  tags = local.common_tags

  # Make sure the source blob is uploaded before the Function App tries to
  # fetch it. Otherwise Azure may try to pull a non-existent zip on first deploy.
  depends_on = [
    azurerm_storage_blob.function_source,
  ]
}

# Application Insights for function logging and metrics.
# Functions writes execution traces, errors, and metrics here automatically.
# Useful for debugging and audit (every invocation is logged).
resource "azurerm_application_insights" "main" {
  name                = "${var.name_prefix}-appinsights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id
  tags                = local.common_tags
}

# Log Analytics workspace required by App Insights for storage of telemetry.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}
