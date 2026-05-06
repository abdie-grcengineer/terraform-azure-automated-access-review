# Azure Automated Access Review

Continuous Azure security posture assessment with policy-as-code guardrails. Built natively on Microsoft Azure.

The system runs on a schedule, pulls findings from native Azure security services, summarizes them with a Microsoft-hosted Phi-4-mini-instruct model on Microsoft Foundry, archives a CSV in Blob Storage, and delivers the report by email via Azure Communication Services. Every infrastructure change is validated against NIST 800-53 / CMMC controls before it touches Azure.

## Why this is GRC engineering

The control IS the code. Infrastructure as code defines the system, policy as code enforces the rules, CI runs the gate on every change. Compliance ships in the same pipeline as the system.

## Architecture

```
                                  ┌─────────────────────────────────────────┐
                                  │  Native Azure Security Sources          │
                                  │   - Azure RBAC (role assignments)       │
                                  │   - Microsoft Defender for Cloud        │
                                  │   - Activity Log                        │
                                  │   - Resource Graph                      │
                                  │   - Microsoft Entra ID (sign-ins)       │
                                  └──────────────┬──────────────────────────┘
                                                 │ read-only via managed identity
                                                 │
                ┌────────────────────────────────┼────────────────────┐
                │                                ▼                    │
   ┌─────────────────────┐               ┌────────────────────┐       │
   │ Cron schedule       │ 5-field cron  │ Container App Job  │       │
   │ trigger             ├──────────────►│ (Python 3.11)      │       │
   │ (monthly, built-in  │               │ User-assigned MI   │       │
   │  to Container Apps) │               │ ACR-hosted image   │       │
   └─────────────────────┘               └────┬──┬─────┬──────┘       │
                                              │  │     │              │
                       ┌──────────────────────┘  │     └─────────┐    │
                       │                         │               │    │
                       ▼                         ▼               ▼    │
            ┌─────────────────────┐  ┌────────────────────┐  ┌─────────────────┐
            │ Microsoft Foundry   │  │ Blob Storage       │  │ Communication   │
            │ (kind=AIServices)   │  │ (HTTPS only, TLS   │  │ Services Email  │
            │ Phi-4-mini-instruct │  │  1.2, versioned,   │  │ (Azure-managed  │
            │ (Entra ID auth)     │  │  lifecycle policy) │  │  sender domain) │
            └─────────────────────┘  └────────────────────┘  └─────────────────┘
```

## Compliance controls enforced

| Policy | NIST 800-53 / CMMC mapping |
| --- | --- |
| `policy/rbac_no_owner.rego` | AC-6 Least Privilege / CMMC AC.L2-3.1.5 |
| `policy/storage_secure.rego` | AC-3 Access Enforcement, SC-7 Boundary Protection / CMMC AC.L2-3.1.3 |
| `policy/storage_encryption.rego` | SC-28 Protection at Rest / CMMC SC.L2-3.13.16 |

## Repository layout

```
.
├── terraform/                 IaC for Storage, Container Apps, Foundry + Phi, ACS, RBAC
├── policy/                    OPA/Rego policies enforcing NIST/CMMC controls
├── scripts/                   bootstrap and operational wrappers
├── src/function/              Python Container App Job implementation (Dockerfile + Python 3.11)
├── docs/                      design decisions, lessons learned, study material
└── .github/workflows/         CI: federated OIDC auth, fmt, tflint, plan, OPA gate, apply
```

## Tech stack

| Layer | Choice |
| --- | --- |
| Infrastructure as Code | Terraform >= 1.10 with `hashicorp/azurerm` provider |
| State management | Azure Storage backend with blob versioning + lease-based locking |
| Policy as Code | OPA / Conftest with Rego v1 |
| CI/CD | GitHub Actions |
| Cloud auth (CI) | Federated identity credentials on Microsoft Entra ID app |
| Compute | Azure Container App Job (Python 3.11, Linux, scales to zero) |
| Scheduler | Container Apps Job built-in cron trigger (5-field, no seconds) |
| AI summary | Microsoft Foundry (`kind = "AIServices"`) hosting Phi-4-mini-instruct, Entra ID auth via the v1 OpenAI-compatible inference endpoint |
| Storage | Blob Storage with HTTPS-only, TLS 1.2, versioning, lifecycle |
| Email | Azure Communication Services Email (Azure-managed sender domain) |
| Secret store | Azure Key Vault |
| Identity for runtime | System-assigned managed identity on the Function App |

## Prerequisites

- Azure subscription with billing enabled
- `az` CLI authenticated (`az login`)
- Terraform >= 1.10
- [Conftest](https://www.conftest.dev/) (`brew install conftest`)
- Microsoft Foundry / Phi-4-mini-instruct available in your target region (eastus2 by default; check `az cognitiveservices account list-models` after the Foundry resource is created)

## One-time bootstrap

The `scripts/bootstrap_azure.sh` script provisions:
- A resource group for Terraform state
- A storage account + blob container for Terraform state (versioned, HTTPS only)
- An Entra ID app registration + service principal for GitHub Actions
- Federated identity credentials for the GitHub repo
- Contributor + User Access Administrator role assignments at subscription scope

Idempotent: running on an account that already has these resources is a no-op.

## Quick start

```bash
# 1. Configure your inputs
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set recipient_email, subscription_id, tenant_id

# 2. Initialize Terraform (connects to the Azure Storage state backend)
terraform init

# 3. Deploy with the policy gate
cd ..
./scripts/tf_deploy.sh

# 4. Trigger an immediate report (HTTP-trigger entry point)
./scripts/tf_run_report.sh
```

## CI/CD

The GitHub Actions workflow at `.github/workflows/terraform.yml` runs on every PR and every push to `main`:

1. Checkout
2. Authenticate to Azure via federated identity credentials (no stored credentials)
3. `terraform fmt -check`
4. `tflint`
5. `terraform plan -input=false`
6. Conftest evaluates all policies under `policy/`
7. Plan artifact uploaded for audit retention
8. Apply, only on push to main, only if all gates pass

## License

MIT
