# Azure Communication Services (ACS) for sending email.
#
# ACS Email is multi-resource:
# 1. azurerm_communication_service: the parent ACS resource.
# 2. azurerm_email_communication_service: the email-specific child service.
# 3. azurerm_email_communication_service_domain: a sender domain. We use the
#    Azure-managed domain so we don't have to verify a custom DNS domain.
# 4. Linking: the parent ACS must be told which email service + domain to use
#    via senderUsernames (handled by code at runtime via the connection string).
#
# Region note: Email Communication Service has limited regional availability.
# "United States" is one of the available data location values.

# Parent ACS resource.
resource "azurerm_communication_service" "main" {
  name                = "${var.name_prefix}-acs"
  resource_group_name = azurerm_resource_group.main.name
  data_location       = "United States"
  tags                = local.common_tags
}

# Email-specific child service.
resource "azurerm_email_communication_service" "main" {
  name                = "${var.name_prefix}-acs-email"
  resource_group_name = azurerm_resource_group.main.name
  data_location       = "United States"
  tags                = local.common_tags
}

# Sender domain. AzureManaged means Azure provisions a *.azurecomm.net domain
# automatically; no DNS records to configure.
# For production, you'd use domain_management = "CustomerManaged" and verify
# DNS records on a domain you own.
resource "azurerm_email_communication_service_domain" "main" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.main.id
  domain_management = "AzureManaged"
}

# Connect the parent ACS to the email service's domain so ACS can send through it.
# Without this, the function code can call ACS but ACS has no sender domain configured.
resource "azurerm_communication_service_email_domain_association" "main" {
  communication_service_id = azurerm_communication_service.main.id
  email_service_domain_id  = azurerm_email_communication_service_domain.main.id
}
