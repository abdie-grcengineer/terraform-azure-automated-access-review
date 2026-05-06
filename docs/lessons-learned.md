# Lessons Learned

Gotchas to expect and the patterns we adopted to prevent repeats.

---

## 1. CI hangs forever when a required variable has no default

`subscription_id`, `tenant_id`, and `recipient_email` are required. Locally they come from `terraform.tfvars` (gitignored). In CI, they must come from secrets via `TF_VAR_<name>` env vars.

**Fix:**
- `-input=false` on every `terraform plan` call in CI. Forces a clean fail instead of a silent hang.
- Pass required variables via `TF_VAR_<name>` env vars sourced from GitHub secrets.

---

## 2. Workflow does not auto-trigger on the commit that introduces it

When path filters are present in `on: push:`, GitHub Actions sometimes does not run the workflow on the commit that adds the workflow file.

**Fix:**
- Include `workflow_dispatch:` in the `on:` block so manual triggers are always available.
- Include `.github/workflows/terraform.yml` in the path filter.

---

## 3. State lock contention from concurrent or cancelled runs

Azure Storage backend uses blob leases for locking. A cancelled run mid-flight can leave a stale lease that blocks subsequent runs.

**Fix:**
- Don't trigger overlapping runs.
- If a run hangs, cancel cleanly first. Check for stale leases on the state blob:
  `az storage blob lease break --container tfstate --blob azure-access-review.tfstate --account-name <state-sa>`

---

## 4. Markdown auto-linking corrupts pasted code

When copy-pasting from rendered markdown, anything that looks like a domain gets auto-linked.

**Fix:**
- Write file content directly via the file-writing tool. Don't ask the user to copy-paste from a code block.

---

## 5. Function App + dependent resource permissions take time to propagate

System-assigned managed identity creation, role assignments, and Function App readiness can take 1-3 minutes on first deploy.

**Fix:**
- Don't ctrl-C a deploy that's "just sitting there" within the first 5 minutes. Wait it out.

---

## 6. Resource provider registration is asynchronous

`az provider register` returns when the request is accepted, not when registration is fully complete. First `terraform apply` can occasionally fail with "subscription is not registered to use namespace".

**Fix:**
- Use `--wait` flag with `az provider register`.
- Bootstrap script does this, with a parallel-wait pattern for speed.

---

## 7. Storage-not-empty blocks storage account deletion

Azure Storage accounts cannot be deleted if they contain blobs unless `force_destroy` allows it. Terraform's `azurerm_storage_account` does not have a force_destroy flag; you must empty the container first.

**Fix:**
- For demo deletion, set `report_storage_force_destroy = true` and the lifecycle resource will help auto-clean.
- For thorough cleanup before destroy: `az storage blob delete-batch --source <container> --account-name <sa>`.

---

## 8. Storage account names are globally unique with strict syntax

3-24 chars, lowercase letters and digits only, no hyphens.

**Fix:**
- Strip hyphens from the name_prefix when forming storage names.
- Append a random suffix to ensure global uniqueness.

---

## 9. Azure OpenAI requires custom subdomain for Entra ID auth

Without `custom_subdomain_name` set on the Cognitive Services account, the account only accepts API key auth, not Entra ID tokens. This blocks the managed-identity-based auth pattern.

**Fix:**
- Always set `custom_subdomain_name` on `azurerm_cognitive_account` resources you want to use with managed identity.
- Set `local_auth_enabled = false` to force Entra-only auth.

---

## 10. NCRONTAB has 6 fields, not 5

Standard cron has 5 fields (minute hour day month dow). Azure Functions Timer trigger uses NCRONTAB which has 6 (second minute hour day month dow). A standard cron expression in NCRONTAB will be misinterpreted.

**Fix:**
- Always include the seconds field. `0 0 8 1 * *` = 08:00:00 on the 1st of every month.

---

## 11. Em dashes in written content

**Standing rule:** No em dashes in user-facing prose. Use commas, parens, or sentence breaks.

---

## 12. Function v2 model needs EnableWorkerIndexing flag

The Python v2 programming model (decorators, no function.json) requires the
app setting `AzureWebJobsFeatureFlags=EnableWorkerIndexing`. Without it, Azure
Functions runtime falls back to v1 and looks for function.json files that
don't exist.

**Fix:**
- Always set this app setting on Linux Function Apps using v2 Python model.

---

## 13. Run-from-package SAS URL must escape correctly

The `WEBSITE_RUN_FROM_PACKAGE` setting takes a full HTTPS URL with a SAS
query string. The SAS includes characters like `&` and `?`; URL-encode any
component values that are themselves URL-like.

**Fix:**
- Construct the URL in Terraform with `${...}.sas` directly, not via string
  concatenation. The `data.azurerm_storage_account_blob_container_sas` output
  already includes the leading `?` for the SAS query string.

---

## 14. Defender for Cloud free tier does not include alerts

The Defender for Cloud (formerly Azure Security Center) free tier provides
recommendations (CSPM) but not threat detection alerts. Calls to
`security_center.alerts.list()` return empty on free tier.

**Fix:**
- The function pulls assessments (recommendations) instead of alerts; works on free tier.
- If you enable a paid Defender plan, alerts become available without code changes.

---

## 15. ACS Email sender domain must be linked

Creating an email service domain alone is not enough. The ACS resource must
have a `azurerm_communication_service_email_domain_association` linking it to
the domain. Without that, ACS sends will fail with "no sender domain configured".

**Fix:**
- Always create the domain association explicitly in Terraform.

---

## 16. Contributor at sub scope is NOT enough for storage backend with use_azuread_auth

The `azurerm` backend with `use_azuread_auth = true` performs data-plane
operations (list blobs, lease blobs) against the state container. Azure RBAC
splits control plane (Owner/Contributor/Reader) from data plane (Storage Blob
Data Owner/Contributor/Reader). Contributor at subscription scope grants
control-plane access to manage the storage account, but it does NOT grant
data-plane access to read or write blobs inside it.

**Symptom:** `terraform init` fails with
`StatusCode=403 Code="AuthorizationPermissionMismatch"` when listing blobs.

**Fix:**
- Grant `Storage Blob Data Owner` to the service principal scoped to the state storage account.
- Run after bootstrap: `az role assignment create --assignee <app-id> --role "Storage Blob Data Owner" --scope <state-sa-resource-id>`.
- Adding to bootstrap_azure.sh would prevent this entirely on fresh installs.

## 17. ARM_CLIENT_ID and ARM_TENANT_ID env vars need to be set on EVERY terraform step in CI

Setting them on plan only is not enough. The `terraform init` step also needs
them because the azurerm provider builds its config during init. Without them,
init fails with `Error building ARM Config: a Tenant ID must be configured`.

**Fix:**
- Apply the `env:` block with all three ARM_* env vars to every terraform step
  (init, plan, apply) in the workflow.

---

## 18. Foundry v1 inference uses a different audience than Azure OpenAI

The dropped Azure OpenAI code used token audience `https://cognitiveservices.azure.com/.default`.
The v1 Foundry inference endpoint uses `https://ai.azure.com/.default`.
Wrong audience produces a 401 with a confusing message; the symptom looks
like an RBAC problem but it is actually an audience problem.

**Fix:**
- For Foundry v1 inference, always use audience `https://ai.azure.com/.default`.
- Reserve `https://cognitiveservices.azure.com/.default` for the older Azure
  OpenAI endpoint shape (which we no longer use).

---

## 19. v1 Foundry endpoint accepts the standard OpenAI client (not AzureOpenAI)

The v1 Foundry inference API is OpenAI-compatible. The standard `OpenAI()`
Python client points at the Foundry endpoint with `base_url` set to
`https://<resource>.openai.azure.com/openai/v1/` (or the equivalent
`services.ai.azure.com` form). The older `AzureOpenAI()` client is no
longer needed for this code path. The `azure-ai-inference` SDK is also
unnecessary and was deprecated in 2026.

**Fix:**
- Use `from openai import OpenAI` (not `AzureOpenAI`).
- Pass a token provider callable as `api_key`: the SDK refreshes tokens automatically.
- `model` parameter on chat completions is the deployment name, not the underlying model name.

---

## 20. ACR Tasks can be subscription-gated; `az acr build` may return TasksOperationsNotAllowed

Some Azure subscription types (free trial, certain pay-as-you-go tiers, sandbox)
have ACR Tasks disabled at the subscription level even when the registry
itself supports Tasks (Basic/Standard/Premium SKUs). The error looks like:

  ERROR: (TasksOperationsNotAllowed) ACR Tasks requests for the registry
  <registry> and <subscription> are not permitted. Please file an Azure
  support request at http://aka.ms/azuresupport for assistance.

Upgrading the registry SKU does not fix this; it is a sub-level feature gate.

**Fix (and the right architecture anyway):**
- Move image build out of Terraform's local-exec into CI.
- The CI runner builds with Docker (`az acr login` + `docker build` + `docker push`)
  and the runner has Docker preinstalled, so no ACR Tasks dependency.
- Terraform then only references the pre-existing `:latest` image. Cleaner
  separation of CI (artifact build) from CD (infra apply).
- Bonus: this is the production pattern. Decoupling artifact build from infra
  apply means a Terraform replan never accidentally rebuilds the image.

---

## 21. ACS Email via managed identity needs an explicit RBAC role on the ACS resource

ACS Email supports two auth modes: connection string (key-based) and Entra ID
(managed identity). When using managed identity, the principal needs an RBAC
role on the ACS resource that grants the data-plane email send action.
Without it, `email_client.begin_send()` returns:

  azure.core.exceptions.ClientAuthenticationError: (Denied) Denied by
  the resource provider.

The error is at the ACS resource provider, not at AAD. It looks like a token
problem but it is actually an RBAC problem.

**Fix:**
- Grant the calling principal `Contributor` scoped to the ACS resource
  (least privilege; sub-scope Contributor would also work but is over-broad).
- The role is in `terraform/identity.tf` as `azurerm_role_assignment.job_acs_contributor`.
- Wait ~30 seconds for RBAC propagation before retesting.

---

(Append new lessons here as they come up.)
