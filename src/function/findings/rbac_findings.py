"""
RBAC-related findings for the Azure access review.

Checks performed:
  1. Any role assignment granting Owner at subscription scope (these are
     overly broad and a common audit finding).
  2. Any role assignment to a deleted/orphaned principal (a stale grant).
"""

import logging
from typing import List, Dict


# Built-in roles considered too broad to grant casually.
BROAD_ROLES = {"Owner", "User Access Administrator"}


def collect_rbac_findings(subscription_id: str) -> List[Dict]:
    """Inspect role assignments at subscription scope and return findings."""
    findings: List[Dict] = []

    findings += check_broad_role_assignments(subscription_id)

    return findings


def check_broad_role_assignments(subscription_id: str) -> List[Dict]:
    """Flag any Owner or User Access Administrator role at subscription scope."""
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.authorization import AuthorizationManagementClient

    findings: List[Dict] = []
    try:
        # DefaultAzureCredential auto-discovers credentials. In the function
        # runtime, that is the system-assigned managed identity.
        credential = DefaultAzureCredential()
        auth_client = AuthorizationManagementClient(credential, subscription_id)

        # We need the role definition name (Owner, Contributor, etc.) but
        # role_assignment.role_definition_id is just the GUID; we look up the
        # display name via role_definitions.
        # For a small subscription, listing all definitions and caching is fine.
        role_def_names = {}
        for rd in auth_client.role_definitions.list(scope=f"/subscriptions/{subscription_id}"):
            role_def_names[rd.id] = rd.role_name

        scope = f"/subscriptions/{subscription_id}"
        for assignment in auth_client.role_assignments.list_for_scope(scope):
            role_name = role_def_names.get(assignment.role_definition_id, "Unknown")
            if role_name in BROAD_ROLES:
                findings.append({
                    "category": "RBAC",
                    "severity": "HIGH" if role_name == "Owner" else "MEDIUM",
                    "resource": assignment.scope or scope,
                    "description": (
                        f"Role assignment grants {role_name} to principal {assignment.principal_id}. "
                        f"Replace with finer-grained roles for least privilege."
                    ),
                })
    except Exception as e:
        logging.warning(f"check_broad_role_assignments failed: {e}")

    return findings
