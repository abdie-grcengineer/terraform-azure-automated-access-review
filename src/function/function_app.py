"""
Azure Functions entrypoint (Python v2 programming model).

The v2 model uses decorators to declare triggers and bindings; no separate
function.json files needed. The file MUST be named function_app.py and the
FunctionApp instance MUST be at module scope for Azure to discover it.

Two triggers:
  - Timer trigger: runs on the configured NCRONTAB schedule (monthly).
  - HTTP trigger: lets us invoke the access review on demand from
    scripts/tf_run_report.sh or curl.
Both call the same business logic.
"""

import json
import logging
import os
from datetime import datetime, timezone

import azure.functions as func

from findings.rbac_findings import collect_rbac_findings
from findings.defender_findings import collect_defender_findings
from findings.activity_log_findings import collect_activity_findings
from narrative import generate_narrative
from reporting import build_csv
from email_sender import send_report_email
from storage_writer import upload_report_to_blob


# FunctionApp instance is the v2-model entrypoint Azure looks for.
app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.timer_trigger(
    schedule=os.environ.get("SCHEDULE_NCRONTAB", "0 0 8 1 * *"),
    arg_name="myTimer",
    run_on_startup=False,
    use_monitor=False,
)
def scheduled_run(myTimer: func.TimerRequest) -> None:
    """Fired by the built-in Timer trigger on the configured schedule."""
    logging.info("Timer trigger fired; starting access review")
    result = run_access_review(trigger="scheduled")
    logging.info(f"Run complete: {result}")


@app.route(route="run", auth_level=func.AuthLevel.FUNCTION, methods=["POST", "GET"])
def manual_run(req: func.HttpRequest) -> func.HttpResponse:
    """Manual entry point. Called by scripts/tf_run_report.sh."""
    logging.info("HTTP trigger fired; starting access review")
    try:
        result = run_access_review(trigger="manual")
        return func.HttpResponse(
            body=json.dumps(result),
            status_code=200,
            mimetype="application/json",
        )
    except Exception as e:
        logging.exception("Run failed")
        return func.HttpResponse(
            body=json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json",
        )


def run_access_review(trigger: str = "unknown") -> dict:
    """The business logic: collect findings, summarize, store, email."""
    subscription_id = os.environ["SUBSCRIPTION_ID"]
    storage_account = os.environ["REPORT_STORAGE_ACCOUNT"]
    container       = os.environ["REPORT_CONTAINER"]
    recipient       = os.environ["RECIPIENT_EMAIL"]
    openai_endpoint = os.environ["OPENAI_ENDPOINT"]
    openai_deployment = os.environ["OPENAI_DEPLOYMENT"]
    acs_endpoint    = os.environ["ACS_ENDPOINT"]
    acs_sender      = os.environ["ACS_SENDER_ADDRESS"]

    # Collect findings from each source. Each function returns a list of dicts
    # with the common shape {category, severity, resource, description}.
    findings = []
    findings += collect_rbac_findings(subscription_id)
    findings += collect_defender_findings(subscription_id)
    findings += collect_activity_findings(subscription_id)

    logging.info(f"Collected {len(findings)} total findings")

    # Build CSV and upload to Blob Storage.
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    blob_name = f"access-review-{timestamp}.csv"
    csv_buffer = build_csv(findings)
    upload_report_to_blob(storage_account, container, blob_name, csv_buffer.getvalue())
    logging.info(f"Report uploaded to https://{storage_account}.blob.core.windows.net/{container}/{blob_name}")

    # Generate the narrative summary via Azure OpenAI.
    narrative = generate_narrative(findings, openai_endpoint, openai_deployment)
    logging.info("Narrative generated")

    # Send the email via ACS Email.
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

    return {
        "trigger": trigger,
        "findings_count": len(findings),
        "report_blob": blob_name,
    }
