# Azure OpenAI service for the narrative summary.
#
# Two resources:
# 1. azurerm_cognitive_account: the Azure OpenAI account (the parent service).
#    Cognitive Services is Microsoft's umbrella for AI services; OpenAI is one
#    "kind" within it.
# 2. azurerm_cognitive_deployment: a model deployment on the account. You can
#    have multiple deployments (different models, different versions) on one
#    account. The function code calls a specific deployment by name.

resource "azurerm_cognitive_account" "openai" {
  name                = "${var.name_prefix}-openai"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = "S0" # Standard tier (the only tier for OpenAI)

  # Disable local authentication (API keys); force callers to use Entra ID.
  # The function uses its managed identity to authenticate.
  local_auth_enabled = false

  # Custom subdomain is required for Entra ID auth on OpenAI accounts.
  # Without it, the account only accepts API key auth.
  custom_subdomain_name = "${var.name_prefix}-openai-${random_string.suffix.result}"

  tags = local.common_tags
}

resource "azurerm_cognitive_deployment" "gpt" {
  name                 = var.openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }

  sku {
    # Standard is regional capacity (vs GlobalStandard which pulls from a
    # global pool). New subscriptions often have 0 GlobalStandard quota but
    # default regional Standard quota for popular models like gpt-4o-mini.
    name     = "Standard"
    capacity = 10 # Tokens-per-minute capacity (units of 1000)
  }
}
