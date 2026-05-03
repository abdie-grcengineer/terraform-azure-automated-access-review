"""
Build the CSV report from the list of findings.

Output schema:
    timestamp,category,severity,resource,description
"""

import csv
import io
from datetime import datetime, timezone
from typing import List, Dict


SEVERITY_ORDER = {
    "CRITICAL": 0,
    "HIGH": 1,
    "MEDIUM": 2,
    "LOW": 3,
    "INFO": 4,
}


def build_csv(findings: List[Dict]) -> io.StringIO:
    """Render findings as a CSV string in an in-memory buffer."""
    findings = sorted(findings, key=lambda f: SEVERITY_ORDER.get(f["severity"], 99))

    buffer = io.StringIO()
    writer = csv.DictWriter(
        buffer,
        fieldnames=["timestamp", "category", "severity", "resource", "description"],
    )
    writer.writeheader()

    timestamp = datetime.now(timezone.utc).isoformat()

    for finding in findings:
        writer.writerow({
            "timestamp": timestamp,
            "category": finding.get("category", "Unknown"),
            "severity": finding.get("severity", "INFO"),
            "resource": finding.get("resource", ""),
            "description": finding.get("description", "").replace("\n", " ").replace("\r", ""),
        })

    return buffer
