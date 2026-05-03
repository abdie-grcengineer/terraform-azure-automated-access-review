# Storage accounts and blob containers for the function: one for reports, plus
# the function's own internal storage requirements (Azure Functions on
# Consumption plan needs an associated general-purpose storage account for
# its runtime metadata, Triggers, and queues).

# Storage account that holds the report CSVs.
# Each storage account has a globally unique name (3-24 chars, lowercase letters
# + digits only). We append a substring of the subscription ID to ensure uniqueness.
resource "azurerm_storage_account" "report" {
  # Storage account names cannot have hyphens; replace with empty string.
  # 24-char limit is hard; we trim to fit.
  name                = substr(replace("${var.name_prefix}rpt${random_string.suffix.result}", "-", ""), 0, 24)
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS" # Locally-redundant; cheapest, sufficient for a demo

  # Security baseline.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false # Equivalent to GCS UBLA + public_access_prevention
  public_network_access_enabled   = true  # Set to false for private-network-only access

  # Encryption at rest is automatic with Microsoft-managed keys; no explicit
  # config needed unless you want customer-managed keys (CMEK).

  blob_properties {
    # Versioning preserves all generations of objects.
    # Equivalent to S3 object versioning or GCS bucket versioning.
    versioning_enabled = true

    # Soft delete keeps deleted blobs recoverable for N days.
    # Helps satisfy "you cannot accidentally lose audit evidence" requirements.
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Random suffix to make storage account names globally unique without leaking
# subscription IDs. Generated once at first apply; persists in state.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Container inside the storage account where reports actually land.
# Containers are like S3 prefixes/folders but they are first-class resources
# with their own access controls.
resource "azurerm_storage_container" "reports" {
  name                  = "reports"
  storage_account_id    = azurerm_storage_account.report.id
  container_access_type = "private" # Never expose audit reports publicly
}

# Lifecycle policy: delete reports older than var.report_retention_days.
# Auto-cleanup prevents unbounded storage cost growth.
# 90 days satisfies common federal retention minimums (FedRAMP, SOC 2).
resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = azurerm_storage_account.report.id

  rule {
    name    = "delete-old-reports"
    enabled = true
    filters {
      prefix_match = ["reports/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.report_retention_days
      }
    }
  }
}
