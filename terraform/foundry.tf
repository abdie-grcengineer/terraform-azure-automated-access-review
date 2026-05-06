# Microsoft Foundry resource (formerly Azure AI Services) hosts the LLM
# we use to generate the executive narrative.
#
# Why Microsoft Foundry, not Azure OpenAI:
# 1. Quota: new Azure subscriptions ship with 0 Azure OpenAI quota across all
#    GA models in our region. Microsoft-direct sold models on Foundry use a
#    separate quota pool with default capacity, so Phi deploys without any
#    quota request to Microsoft Support.
# 2. Compliance posture: Phi models are trained, owned, and hosted by
#    Microsoft. The model and the hosting service both sit under Azure AI
#    Services' FedRAMP High and DoD IL5 attestations. There is no third-party
#    model provenance to defend in a supply-chain audit.
# 3. Cost: at our workload size (one summary per month, ~25K input tokens),
#    inference is rounding-error cents per year regardless of model.
# 4. Architecture: kind = "AIServices" is the unified Foundry resource that
#    supports OpenAI-format and Microsoft-format models behind a single
#    OpenAI-compatible v1 inference endpoint.
#
# Why Phi-4-mini-instruct specifically:
# - Microsoft-trained, Microsoft-owned, Microsoft-hosted (clean provenance)
# - Sold directly by Azure (no Marketplace subscription resource needed)
# - 3.8B params: enough quality to summarize a CSV of findings, low cost
# - GA availability in eastus2 with the GlobalStandard SKU

# Foundry resource (AIServices flavor of Cognitive Services).
# Two settings worth calling out:
#   - local_auth_enabled = false: forces Entra ID auth. No API keys exist.
#     The job's user-assigned managed identity authenticates with a bearer
#     token. Map: NIST 800-53 IA-2(8), CMMC IA.L2-3.5.3 (replay-resistant auth)
#   - custom_subdomain_name: required for Entra ID auth on Cognitive Services.
#     Without it, the account only accepts API key auth.
resource "azurerm_cognitive_account" "foundry" {
  # Subdomain becomes part of the public DNS name. Must be globally unique,
  # 2-64 chars, lowercase alphanumeric and hyphens. Strip underscores from
  # the prefix to be safe.
  name                = substr(replace("${var.name_prefix}-foundry-${random_string.suffix.result}", "_", "-"), 0, 64)
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "AIServices"
  sku_name            = "S0"

  # Force Entra ID auth (no API keys).
  local_auth_enabled = false

  # Custom subdomain is required for Entra ID auth on Cognitive Services.
  custom_subdomain_name = substr(replace("${var.name_prefix}-foundry-${random_string.suffix.result}", "_", "-"), 0, 64)

  # System-assigned identity on the Foundry resource itself. Not used by the
  # job (the job has its own user-assigned MI), but useful if Foundry ever
  # needs to call out to other Azure services (Storage, Key Vault) on its
  # own behalf for things like content filters or fine-tuning.
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Model deployment under the Foundry resource.
# In Cognitive Services terminology:
#   - account: the parent resource (created above)
#   - deployment: a named instance of a model running on that account
# A single account can host multiple deployments (different models or versions);
# the application calls a specific deployment by name in chat completions.
#
# Values come from `az cognitiveservices account list-models`. For
# Phi-4-mini-instruct as of 2026 the canonical values are:
#   format:   Microsoft     (publisher; Microsoft for Phi family)
#   name:     Phi-4-mini-instruct
#   version:  1
#   sku:      GlobalStandard (regional capacity pulled from a global pool)
#   capacity: 1              (units of 1000 tokens-per-minute)
resource "azurerm_cognitive_deployment" "phi" {
  name                 = var.foundry_deployment_name
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "Microsoft"
    name    = var.foundry_model_name
    version = var.foundry_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = 1
  }
}

# The endpoint URL used by the function code to call the model.
# Format: https://<custom-subdomain>.openai.azure.com  (OpenAI v1-compatible
# host name, accepted by the Foundry inference API per Microsoft's v1 API doc).
# The function appends "/openai/v1/" itself.
locals {
  foundry_endpoint = "https://${azurerm_cognitive_account.foundry.custom_subdomain_name}.openai.azure.com"
}
