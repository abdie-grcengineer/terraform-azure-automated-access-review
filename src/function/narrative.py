"""
Generate the executive-summary narrative for the access review report.

Inference target: Microsoft Foundry (formerly Azure AI Services), specifically
a Phi-4-mini-instruct deployment created via Terraform in foundry.tf.

We call the v1 Foundry inference endpoint, which is OpenAI-compatible. That
means we use the standard OpenAI Python SDK (not AzureOpenAI, not the
azure-ai-inference SDK) with two non-default settings:

  1. base_url points at the Foundry resource's openai/v1 path:
       https://<custom-subdomain>.openai.azure.com/openai/v1/
  2. api_key is a token provider callable (from azure-identity) that
     returns a fresh Entra ID bearer token. The OpenAI v1 SDK accepts a
     callable here and refreshes automatically as tokens expire.

Auth: the Container App Job's user-assigned managed identity acquires a
token with audience "https://ai.azure.com/.default". The job's MI must hold
the "Cognitive Services OpenAI User" role on the Foundry resource (granted
in terraform/identity.tf). No API keys are issued or stored anywhere.

Compliance posture: Phi-4-mini-instruct is a Microsoft-trained, Microsoft-
hosted model running inside Azure AI Services. Azure AI Services holds
FedRAMP High authorization in Azure Commercial and DoD IL5 in Azure
Government. By using a Microsoft-published model, we eliminate third-party
model provenance from any future supply-chain audit.
"""

import logging
from collections import Counter
from typing import List, Dict


def generate_narrative(findings: List[Dict], endpoint: str, deployment: str) -> str:
    """
    Call the Foundry v1 inference endpoint and return the narrative summary.

    On any failure (missing config, auth error, model error, network error)
    we fall back to a deterministic template summary so the report email
    still goes out. A degraded narrative is better than no email.
    """
    # Short-circuit when no endpoint is configured. This path is hit during
    # local development or when the Foundry resource hasn't been provisioned
    # yet. Production deploys always have these set via Terraform.
    if not endpoint or not deployment:
        logging.info("Foundry endpoint not configured; using fallback summary.")
        return _fallback_summary(findings)

    try:
        # Imports inside the function so unit tests that don't exercise the
        # AI path don't need azure-identity or openai installed at import time.
        from openai import OpenAI
        from azure.identity import DefaultAzureCredential, get_bearer_token_provider

        # Audience for the Foundry inference endpoint. NOT cognitiveservices.azure.com
        # (that's the older Azure OpenAI audience). The v1 Foundry API requires
        # the ai.azure.com audience.
        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(),
            "https://ai.azure.com/.default",
        )

        # The v1 Foundry endpoint is OpenAI-compatible. We use the standard
        # OpenAI client (not AzureOpenAI), pointed at the Foundry resource's
        # openai/v1 path, with the token provider as the api_key. The SDK
        # treats a callable here as "fetch a fresh token before each call."
        client = OpenAI(
            base_url=f"{endpoint}/openai/v1/",
            api_key=token_provider,
        )

        prompt = _build_prompt(findings)

        response = client.chat.completions.create(
            model=deployment,  # name of the deployment created in Terraform
            messages=[
                {
                    "role": "system",
                    "content": "You are a GRC engineer summarizing Azure security findings for an executive audience.",
                },
                {"role": "user", "content": prompt},
            ],
            max_tokens=600,
        )

        return (response.choices[0].message.content or "").strip()

    except Exception as e:
        logging.warning(f"Foundry inference failed, using fallback summary: {e}")
        return _fallback_summary(findings)


def _build_prompt(findings: List[Dict]) -> str:
    """Compose the prompt sent to the model."""
    by_category = Counter(f["category"] for f in findings)
    by_severity = Counter(f["severity"] for f in findings)

    top = findings[:10]
    top_text = "\n".join(
        f"- [{f['severity']}] {f['category']}: {f['description'][:200]}"
        for f in top
    )

    return f"""Summarize the results of an automated Azure access review.

Total findings: {len(findings)}
By category: {dict(by_category)}
By severity: {dict(by_severity)}

Top findings:
{top_text}

Write a 3-paragraph executive summary that includes:
1. The overall security posture (good, mixed, concerning).
2. The 2-3 most pressing issues that need attention.
3. Recommended next steps for the security team.

Do not include preamble or sign-off; produce only the body text. Be direct, specific, no filler."""


def _fallback_summary(findings: List[Dict]) -> str:
    """Plain-text summary used when the inference path is unavailable."""
    by_severity = Counter(f["severity"] for f in findings)
    by_category = Counter(f["category"] for f in findings)

    return (
        f"Azure Access Review summary (AI narrative unavailable, basic counts only).\n\n"
        f"Total findings: {len(findings)}.\n"
        f"By severity: {dict(by_severity)}.\n"
        f"By category: {dict(by_category)}.\n\n"
        f"Review the attached CSV for full details."
    )
