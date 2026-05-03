"""
Upload the CSV report to Azure Blob Storage using the function's managed identity.
"""

import logging


def upload_report_to_blob(storage_account: str, container: str, blob_name: str, content: str) -> None:
    """Upload a CSV string to the configured Blob container."""
    from azure.identity import DefaultAzureCredential
    from azure.storage.blob import BlobServiceClient

    account_url = f"https://{storage_account}.blob.core.windows.net"
    credential = DefaultAzureCredential()

    blob_service = BlobServiceClient(account_url=account_url, credential=credential)
    blob_client = blob_service.get_blob_client(container=container, blob=blob_name)

    blob_client.upload_blob(
        content.encode("utf-8"),
        overwrite=True,
        content_settings=_content_settings(),
    )

    logging.info(f"Uploaded report to {account_url}/{container}/{blob_name}")


def _content_settings():
    from azure.storage.blob import ContentSettings
    return ContentSettings(content_type="text/csv")
