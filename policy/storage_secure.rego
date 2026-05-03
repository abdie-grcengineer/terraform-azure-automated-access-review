# Policy: every Azure Storage account must be configured for secure access:
# HTTPS-only traffic, modern TLS, no public blob access, minimum TLS 1.2.
#
# Mapping:
#   NIST 800-53 AC-3 (Access Enforcement), SC-7 (Boundary Protection),
#   SC-8 (Transmission Confidentiality and Integrity)
#   CMMC AC.L2-3.1.3

package terraform.storage.secure

import rego.v1

deny contains msg if {
    some resource in input.resource_changes
    resource.type == "azurerm_storage_account"

    some action in resource.change.actions
    action != "delete"

    not resource.change.after.https_traffic_only_enabled

    msg := sprintf(
        "Storage account %s allows non-HTTPS traffic (violates NIST 800-53 SC-8)",
        [resource.address],
    )
}

deny contains msg if {
    some resource in input.resource_changes
    resource.type == "azurerm_storage_account"

    some action in resource.change.actions
    action != "delete"

    resource.change.after.min_tls_version != "TLS1_2"

    msg := sprintf(
        "Storage account %s does not enforce TLS 1.2 minimum (violates NIST 800-53 SC-8)",
        [resource.address],
    )
}

deny contains msg if {
    some resource in input.resource_changes
    resource.type == "azurerm_storage_account"

    some action in resource.change.actions
    action != "delete"

    resource.change.after.allow_nested_items_to_be_public

    msg := sprintf(
        "Storage account %s allows public blob access (violates NIST 800-53 AC-3)",
        [resource.address],
    )
}
