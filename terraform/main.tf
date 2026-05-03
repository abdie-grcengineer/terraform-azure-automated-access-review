# Terraform's spine: required versions, providers, backend, and lookups for
# subscription-level data we need elsewhere.

terraform {
  # Pin Terraform to a recent stable version.
  required_version = ">= 1.10.0"

  # Azure Storage backend stores Terraform state in a Blob container.
  # The storage account itself was created by scripts/bootstrap_azure.sh because
  # of the bootstrap problem: you cannot Terraform-create the resource that
  # holds Terraform state.
  #
  # Locking is handled by blob leases (built-in to Azure Storage). When you run
  # terraform plan or apply, Terraform acquires a lease on the state blob;
  # concurrent runs are blocked until the lease is released.
  backend "azurerm" {
    resource_group_name  = "rg-tf-state"
    storage_account_name = "abditfstateazure68530"
    container_name       = "tfstate"
    key                  = "azure-access-review.tfstate"
    use_azuread_auth     = true
  }

  # Providers are plugins that translate Terraform's resource declarations into
  # API calls. azurerm is the main Azure provider; archive zips local files.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure provider.
# The features {} block is required (it can be empty); it configures provider
# behavior for resource lifecycle scenarios. We use defaults.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# Pull metadata about the current subscription. Used in role assignment scopes
# and for the function's runtime environment variables.
data "azurerm_subscription" "current" {}

# Create the resource group that contains every resource we deploy.
# In Azure, resource groups are containers that group related resources for
# lifecycle management, billing, and access control.
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.name_prefix}"
  location = var.location

  tags = {
    Project   = var.name_prefix
    ManagedBy = "Terraform"
  }
}

# Locals are computed values reused across the configuration.
locals {
  # Common tags applied to every resource. Azure does not have provider-level
  # default_tags like AWS does (the azurerm provider has it as preview but it
  # is not stable enough for production), so we apply tags via this local.
  common_tags = {
    Project   = var.name_prefix
    ManagedBy = "Terraform"
  }
}
