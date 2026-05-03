"""
Send the access review report via Azure Communication Services Email.

Auth: the function uses its managed identity. ACS supports Entra ID auth
for the data plane (sending email); no connection string needed.
The MI is granted the appropriate role on the ACS resource via Terraform.
"""

import base64
import logging


def send_report_email(
    acs_endpoint: str,
    sender: str,
    recipient: str,
    subject: str,
    narrative: str,
    csv_attachment: str,
    csv_filename: str,
) -> None:
    """Send a multipart email via ACS Email."""
    from azure.communication.email import EmailClient
    from azure.identity import DefaultAzureCredential

    credential = DefaultAzureCredential()
    email_client = EmailClient(endpoint=acs_endpoint, credential=credential)

    message = {
        "senderAddress": sender,
        "recipients": {
            "to": [{"address": recipient}],
        },
        "content": {
            "subject": subject,
            "plainText": narrative,
        },
        "attachments": [
            {
                "name": csv_filename,
                "contentType": "text/csv",
                "contentInBase64": base64.b64encode(csv_attachment.encode("utf-8")).decode(),
            },
        ],
    }

    poller = email_client.begin_send(message)
    result = poller.result()
    logging.info(f"ACS email sent. Message ID: {getattr(result, 'id', 'n/a')}")
