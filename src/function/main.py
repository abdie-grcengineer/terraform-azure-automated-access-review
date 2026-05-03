"""
Container App Job entrypoint for the Azure Access Review.

Plain Python script (no Azure Functions decorators) because we run inside a
Container App Job, not the Functions runtime. The Container App Job's
schedule trigger invokes this on a cron schedule; manual invocations use
`az containerapp job start`.

The job runs to completion, exits with code 0 on success or non-zero on
failure. Container Apps captures stdout/stderr to Log Analytics.
"""

import logging
import os
import sys
from datetime import datetime, timezone

# Same module imports as before; logic is unchanged.
from findings.rbac_findings import collect_rbac_findings
from findings.defender_findings import collect_defender_findings
from findings.activity_log_findings import collect_activity_findings
from narrative import generate_narrative
from reporting import build_csv
from email_sender import send_report_email
from storage_writer import upload_report_to_blob


# Configure root logger to write to stdout so Container Apps captures it.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    stream=sys.stdout,
)


def main() -> int:
    subscription_id   = os.environ["SUBSCRIPTION_ID"]
    storage_account   = os.environ["REPORT_STORAGE_ACCOUNT"]
    container         = os.environ["REPORT_CONTAINER"]
    recipient         = os.environ["RECIPIENT_EMAIL"]
    openai_endpoint   = os.environ["OPENAI_ENDPOINT"]
    openai_deployment = os.environ["OPENAI_DEPLOYMENT"]
    acs_endpoint      = os.environ["ACS_ENDPOINT"]
    acs_sender        = os.environ["ACS_SENDER_ADDRESS"]

    logging.info(f"Starting access review for subscription {subscription_id}")

    findings = []
    findings += collect_rbac_findings(subscription_id)
    findings += collect_defender_findings(subscription_id)
    findings += collect_activity_findings(subscription_id)

    logging.info(f"Collected {len(findings)} total findings")

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    blob_name = f"access-review-{timestamp}.csv"
    csv_buffer = build_csv(findings)
    upload_report_to_blob(storage_account, container, blob_name, csv_buffer.getvalue())
    logging.info(f"Report uploaded to https://{storage_account}.blob.core.windows.net/{container}/{blob_name}")

    narrative = generate_narrative(findings, openai_endpoint, openai_deployment)
    logging.info("Narrative generated")

    send_report_email(
        acs_endpoint=acs_endpoint,
        sender=acs_sender,
        recipient=recipient,
        subject=f"Azure Access Review - {timestamp}",
        narrative=narrative,
        csv_attachment=csv_buffer.getvalue(),
        csv_filename=blob_name,
    )
    logging.info(f"Email sent to {recipient}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
