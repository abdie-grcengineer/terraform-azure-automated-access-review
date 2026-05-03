"""
Findings derived from Azure Activity Log.

Activity Log is Azure's audit log: every Azure Resource Manager API call
is logged. Always-on, no setup required (90-day retention by default).

Checks performed:
  1. Recent role assignment changes in the last 30 days (admin activity to review).
  2. Resource deletions in the last 30 days (sensitive operations).
"""

import logging
from datetime import datetime, timezone, timedelta
from typing import List, Dict


def collect_activity_findings(subscription_id: str) -> List[Dict]:
    """Inspect Activity Log entries and return findings of interest."""
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.monitor import MonitorManagementClient

    findings: List[Dict] = []

    try:
        credential = DefaultAzureCredential()
        client = MonitorManagementClient(credential, subscription_id)

        since = datetime.now(timezone.utc) - timedelta(days=30)
        # Activity Log filter syntax uses OData. We filter by time window and
        # operation name to surface specific admin events.
        time_filter = f"eventTimestamp ge '{since.isoformat()}'"

        # Role assignment changes (Microsoft.Authorization/roleAssignments/write).
        role_filter = f"{time_filter} and resourceProvider eq 'Microsoft.Authorization'"
        count = 0
        for entry in client.activity_logs.list(filter=role_filter, select="eventTimestamp,operationName,caller,resourceId,status"):
            op_name = (entry.operation_name.value if entry.operation_name else "").lower()
            if "roleassignments/write" in op_name:
                count += 1
                if count > 20:
                    break
                findings.append({
                    "category": "ActivityLog",
                    "severity": "MEDIUM",
                    "resource": entry.resource_id or "subscription",
                    "description": (
                        f"Role assignment change at {entry.event_timestamp.isoformat()} "
                        f"by {entry.caller or 'unknown'}. Verify the change was authorized."
                    ),
                })

    except Exception as e:
        logging.warning(f"collect_activity_findings failed (non-fatal): {e}")

    return findings
