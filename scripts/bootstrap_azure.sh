#!/bin/bash
# One-time bootstrap of Azure foundation resources Terraform cannot manage itself:
#   - Resource providers registered
#   - Resource group for state
#   - Storage account + container for Terraform state (versioned, HTTPS only)
#   - Entra ID app registration + service principal for GitHub Actions
#   - Federated identity credentials for the GitHub repo
#   - Role assignments (Contributor + User Access Administrator) at sub scope
#
# Idempotent: running on an account that already has these resources is a no-op.

set -e

# === Edit these for your account ===
GH_OWNER="abdie-grcengineer"
GH_REPO="terraform-azure-automated-access-review"
LOCATION="eastus"
RG_NAME="rg-tf-state"
APP_NAME="github-actions-tf-azure-access-review"
# ===================================

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SA_SUFFIX=$(date +%s | tail -c 6)
SA_NAME="abditfstateazure${SA_SUFFIX}"

echo "Subscription: $SUBSCRIPTION_ID"
echo "Tenant:       $TENANT_ID"
echo ""

echo "=== [1/8] Register required resource providers ==="
for ns in Microsoft.Storage Microsoft.Web Microsoft.Insights Microsoft.CognitiveServices Microsoft.Communication Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights; do
  az provider register --namespace "$ns" --wait >/dev/null &
done
wait
echo "Providers registered."

echo ""
echo "=== [2/8] Create resource group for state ==="
az group create --name "$RG_NAME" --location "$LOCATION" --output none

echo ""
echo "=== [3/8] Create storage account for state ==="
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none

echo ""
echo "=== [4/8] Enable versioning + create state container ==="
az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --enable-versioning true \
  --output none

az storage container create \
  --name tfstate \
  --account-name "$SA_NAME" \
  --auth-mode login \
  --output none

echo ""
echo "=== [5/8] Create Entra ID app registration ==="
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "$APP_ID" ]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
fi

SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)
if [ -z "$SP_ID" ]; then
  SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
fi

echo "App ID:           $APP_ID"
echo "Service Princ:    $SP_ID"

echo ""
echo "=== [6/8] Federated identity credentials ==="
for SUBJECT in "ref:refs/heads/main" "pull_request"; do
  CRED_NAME=$(echo "github-${SUBJECT}" | tr ':/' '--')
  EXISTS=$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='$CRED_NAME'] | length(@)" -o tsv)
  if [ "$EXISTS" = "0" ]; then
    az ad app federated-credential create \
      --id "$APP_ID" \
      --parameters "{
        \"name\": \"$CRED_NAME\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"repo:${GH_OWNER}/${GH_REPO}:${SUBJECT}\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }" --output none
    echo "  added: $SUBJECT"
  else
    echo "  already exists: $SUBJECT"
  fi
done

echo ""
echo "=== [7/8] Role assignments at subscription scope ==="
for ROLE in "Contributor" "User Access Administrator"; do
  az role assignment create \
    --assignee "$APP_ID" \
    --role "$ROLE" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --output none 2>/dev/null || echo "  ($ROLE may already exist)"
  echo "  attached: $ROLE"
done

echo ""
echo "=== [8/8] Output config ==="
echo ""
echo "================================================================"
echo "Bootstrap complete. Save these values:"
echo "================================================================"
echo "AZURE_SUBSCRIPTION_ID:  $SUBSCRIPTION_ID"
echo "AZURE_TENANT_ID:        $TENANT_ID"
echo "AZURE_CLIENT_ID:        $APP_ID"
echo "STATE_RG:               $RG_NAME"
echo "STATE_SA:               $SA_NAME"
echo "STATE_CONTAINER:        tfstate"
echo ""
echo "Set as GitHub repo secrets:"
echo "  gh secret set AZURE_SUBSCRIPTION_ID --body \"$SUBSCRIPTION_ID\""
echo "  gh secret set AZURE_TENANT_ID       --body \"$TENANT_ID\""
echo "  gh secret set AZURE_CLIENT_ID       --body \"$APP_ID\""
echo "================================================================"
