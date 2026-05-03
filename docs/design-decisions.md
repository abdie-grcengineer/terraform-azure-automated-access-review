# Design Decisions Log

Running list of key architectural choices for the Azure Automated Access Review. Each entry: what we picked, what we considered, why.

Use this file as the source of truth for "why didn't you do X?" interview questions.

---

## AI service for narrative summary: Azure OpenAI GPT-4o-mini

**Picked:** Azure OpenAI Service with `gpt-4o-mini` deployment

**Considered:**
- GPT-4o (more capable, more expensive)
- GPT-3.5-turbo (older, cheaper, lower quality)
- Anthropic Claude via Azure (limited availability, requires special procurement)

**Why GPT-4o-mini:**
- Azure-native, no third-party model marketplace approval
- Right-sized for summarization workload; the task is summarizing a CSV of findings into a paragraph
- Significantly cheaper per token than GPT-4o; minimal quality loss for summarization
- GPT-4o-mini is the default cheap-and-fast tier on Azure OpenAI

**Interview talking point:**
"GPT-4o-mini is the right size for summarization. Using a larger model would be 5-10x the cost for marginal quality lift on a paragraph of findings. Right-sizing the model to the workload is a cost-and-performance discipline."

---

## Compute service: Azure Functions

**Picked:** Azure Functions on Consumption plan (Python 3.11)

**Considered:**
- Azure Container Apps (more flexibility, container-based)
- App Service (longer-running web apps)
- Logic Apps (low-code orchestration)

**Why Azure Functions on Consumption:**
- Direct serverless model (upload Python, Azure runs it, pay-per-execution)
- Built-in Timer trigger eliminates the need for a separate scheduler resource
- Consumption plan scales to zero between invocations; cost is essentially zero for a monthly run
- Python 3.11 supported runtime

**Interview talking point:**
"Azure Functions on Consumption plan for a periodic batch workload like this access review. Container Apps would be needed for long-running services or container-specific dependencies. For schedule-triggered short-lived work, Functions is the right fit. The built-in Timer trigger is also cleaner than wiring up a separate scheduler resource."

---

## Email delivery: Azure Communication Services Email

**Picked:** Azure Communication Services Email with an Azure-managed sending domain

**Considered:**
- SendGrid (third-party SaaS, cheapest setup)
- Office 365 SMTP (requires user mailbox)
- Skip email and write only to Blob Storage

**Why ACS Email:**
- Azure-native, no third-party signup
- Azure-managed domain (`<random>.azurecomm.net`) ships immediately, no DNS setup
- Pay-per-message pricing, very low cost for monthly reports
- Integrates with Managed Identity for auth, no API keys

**Tradeoff:**
- The Azure-managed domain looks like a no-reply automated address, not personal-branded
- For production with a custom from-address, you'd verify your own domain in ACS

---

## Authentication: Federated identity credentials on Entra ID app

**Picked:** OIDC federation between GitHub Actions and Microsoft Entra ID

**Considered:**
- Service principal with client secret stored in GitHub Secrets (long-lived, audit risk)
- Service principal with certificate (more complex, similar audit profile)

**Why federated identity credentials:**
- No long-lived credentials anywhere
- Tokens are short-lived, scoped per workflow run
- GitHub Actions presents an OIDC token to Entra ID, which exchanges it for a short-lived access token
- Maps to NIST 800-53 IA-2(8) for replay-resistant authentication

**Two-layer security:**
1. Federated credential `subject` claim restricts to specific repo + branch (e.g., `repo:abdie-grcengineer/terraform-azure-automated-access-review:ref:refs/heads/main`).
2. Entra ID app's role assignments scope what the principal can do once authenticated.

---

## State backend: Azure Storage with versioning

**Picked:** Azure Blob Storage backend (`azurerm` Terraform backend), versioning enabled

**Considered:**
- Terraform Cloud (managed)
- Local state (insecure for team use)

**Why Azure Storage backend:**
- Native Azure, no third-party dependency
- Versioning provides rollback for state corruption
- Encryption is automatic at rest (Microsoft-managed keys by default)
- Built-in lease-based locking via blob leases; no separate lock table needed

---

## Identity model (Azure RBAC)

**Pattern:** Azure RBAC uses role assignments at a scope.

You assign a principal (user, group, service principal, managed identity) to a built-in or custom role at a scope (management group, subscription, resource group, individual resource). The "policy" on a resource is the union of all role assignments at all enclosing scopes.

**Use built-in roles** where possible. They are maintained by Microsoft and named consistently. Custom roles introduce maintenance overhead.

**Implication for OPA policies:** the Rego policies target `azurerm_role_assignment` resources to detect over-permissive role assignments.

---

## OPA policies (planned)

Three policies will mirror the AWS and GCP versions, adapted for Azure resource types:

| Policy | Control mapping |
| --- | --- |
| `rbac_no_owner.rego` | NIST 800-53 AC-6 / CMMC AC.L2-3.1.5 (no `Owner` role assignments at subscription scope) |
| `storage_secure.rego` | NIST 800-53 AC-3, SC-7 / CMMC AC.L2-3.1.3 (storage account: HTTPS only, public network access disabled, blob public access disabled) |
| `storage_encryption.rego` | NIST 800-53 SC-28 / CMMC SC.L2-3.13.16 (storage account encryption + soft delete enforced) |

---

(Append new decisions here as we make them.)
