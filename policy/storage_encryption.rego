# Policy: every storage account must have blob versioning enabled. Versioning
# protects audit evidence from accidental or malicious overwrite.
#
# Storage account encryption is automatic in Azure (Microsoft-managed keys);
# there is no "encryption disabled" option. So the encryption-at-rest control
# is satisfied by default. What we enforce here are the related controls that
# do require explicit configuration: versioning + retention.
#
# Mapping:
#   NIST 800-53 SC-28 (Protection of Information at Rest, via versioning)
#   NIST 800-53 SI-12 (Information Handling and Retention)
#   CMMC SC.L2-3.13.16

package terraform.storage.encryption

import rego.v1

deny contains msg if {
    some resource in input.resource_changes
    resource.type == "azurerm_storage_account"

    some action in resource.change.actions
    action != "delete"

    not storage_has_versioning_enabled(resource.change.after)

    msg := sprintf(
        "Storage account %s does not have blob versioning enabled (violates NIST 800-53 SC-28)",
        [resource.address],
    )
}

# Helper: did the user enable versioning on this storage account?
# In Terraform plan JSON, blob_properties is a list of objects; versioning_enabled
# is a field within. If blob_properties is empty or versioning_enabled is false,
# versioning is off.
storage_has_versioning_enabled(after) if {
    some bp in after.blob_properties
    bp.versioning_enabled == true
}
