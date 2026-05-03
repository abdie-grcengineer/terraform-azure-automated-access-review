"""
Findings from Microsoft Defender for Cloud.

Defender for Cloud aggregates security alerts and recommendations across the
subscription. Free tier provides Foundational CSPM (recommendations); Defender
plans (paid) add threat detection alerts.

If Defender is not enabled, calls return empty lists; non-fatal.
"""

import logging
from typing import List, Dict


def collect_defender_findings(subscription_id: str) -> List[Dict]:
    """Pull Defender for Cloud findings; return as a list of finding dicts."""
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.security import SecurityCenter

    findings: List[Dict] = []

    try:
        credential = DefaultAzureCredential()
        # SecurityCenter SDK requires an asc_location even though most APIs are
        # global; "centralus" or any region works for the SDK init.
        sc_client = SecurityCenter(credential, subscription_id, asc_location="centralus")

        # Pull active recommendations (CSPM signal).
        for assessment in sc_client.assessments.list(scope=f"/subscriptions/{subscription_id}"):
            if hasattr(assessment, "status") and assessment.status:
                if str(assessment.status.code).lower() == "unhealthy":
                    findings.append({
                        "category": "Defender",
                        "severity": _normalize_severity(getattr(assessment.metadata, "severity", "Medium") if hasattr(assessment, "metadata") else "Medium"),
                        "resource": assessment.resource_details.id if hasattr(assessment, "resource_details") and assessment.resource_details else "subscription",
                        "description": (
                            f"{getattr(assessment, 'display_name', 'Recommendation')}: "
                            f"{getattr(assessment.status, 'description', '')}"
                        ),
                    })
    except Exception as e:
        # Defender may not be enabled or accessible; non-fatal.
        logging.warning(f"collect_defender_findings failed (non-fatal): {e}")

    return findings


def _normalize_severity(severity: str) -> str:
    """Normalize Defender severity strings to our common scale."""
    s = (severity or "").lower()
    if s == "high":
        return "HIGH"
    if s == "medium":
        return "MEDIUM"
    if s == "low":
        return "LOW"
    return "INFO"
