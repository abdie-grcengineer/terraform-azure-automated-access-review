# Policy: no Owner role assignments at subscription scope via Terraform.
# Owner is the broadest built-in role in Azure RBAC; granting it via IaC is
# almost always a mistake. Modern guidance: use Contributor + finer-grained
# roles for what users actually need.
#
# Mapping:
#   NIST 800-53 AC-6 (Least Privilege)
#   CMMC AC.L2-3.1.5

package terraform.rbac.no_owner

import rego.v1

# Roles considered too broad to grant via Terraform.
# "Owner" is the most dangerous (full control, including delegating access).
# "Contributor" can manage resources but cannot grant access.
forbidden_roles := {"Owner", "User Access Administrator"}

deny contains msg if {
    some resource in input.resource_changes
    resource.type == "azurerm_role_assignment"

    some action in resource.change.actions
    action != "delete"

    forbidden_roles[resource.change.after.role_definition_name]

    msg := sprintf(
        "Role assignment %s grants forbidden role %s (violates NIST 800-53 AC-6 least privilege)",
        [resource.address, resource.change.after.role_definition_name],
    )
}
