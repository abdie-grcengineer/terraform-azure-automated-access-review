"""
Generate the executive-summary narrative for the report using Azure OpenAI.

Auth: the function uses its system-assigned managed identity to call the
OpenAI endpoint. No API keys; identity is presented as an Entra ID token.
The function's MI must have the "Cognitive Services OpenAI User" role on the
OpenAI account (granted in terraform/identity.tf).
"""

import logging
from collections import Counter
from typing import List, Dict


def generate_narrative(findings: List[Dict], endpoint: str, deployment: str) -> str:
    """Call Azure OpenAI and return the narrative summary."""
    try:
        from openai import AzureOpenAI
        from azure.identity import DefaultAzureCredential, get_bearer_token_provider

        # token_provider returns a bearer token for Azure OpenAI on each call.
        # DefaultAzureCredential picks up the function's managed identity at runtime.
        credential = DefaultAzureCredential()
        token_provider = get_bearer_token_provider(
            credential,
            "https://cognitiveservices.azure.com/.default",
        )

        client = AzureOpenAI(
            api_version="2024-08-01-preview",
            azure_endpoint=endpoint,
            azure_ad_token_provider=token_provider,
        )

        prompt = _build_prompt(findings)

        response = client.chat.completions.create(
            model=deployment,  # In Azure OpenAI, "model" is the deployment name
            messages=[
                {"role": "system", "content": "You are a GRC engineer summarizing Azure security findings for an executive audience."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=600,
        )

        return (response.choices[0].message.content or "").strip()

    except Exception as e:
        logging.warning(f"Azure OpenAI generation failed, using fallback: {e}")
        return _fallback_summary(findings)


def _build_prompt(findings: List[Dict]) -> str:
    """Compose the prompt for the model."""
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
    """Plain-text summary when OpenAI is unavailable."""
    by_severity = Counter(f["severity"] for f in findings)
    by_category = Counter(f["category"] for f in findings)

    return (
        f"Azure Access Review summary (AI narrative unavailable, basic counts only).\n\n"
        f"Total findings: {len(findings)}.\n"
        f"By severity: {dict(by_severity)}.\n"
        f"By category: {dict(by_category)}.\n\n"
        f"Review the attached CSV for full details."
    )
