#!/bin/bash
# Manually trigger the access review function via its HTTP endpoint.
# The function has both a Timer trigger (for the schedule) and an HTTP trigger
# (for manual invocation). This script calls the HTTP endpoint with the
# function's master key for auth.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

if [ ! -d "$TERRAFORM_DIR/.terraform" ]; then
  echo "Error: $TERRAFORM_DIR is not initialized. Run 'terraform init' first."
  exit 1
fi

RG=$(terraform -chdir="$TERRAFORM_DIR" output -raw resource_group 2>/dev/null)
FUNC=$(terraform -chdir="$TERRAFORM_DIR" output -raw function_name 2>/dev/null)
HOST=$(terraform -chdir="$TERRAFORM_DIR" output -raw function_default_hostname 2>/dev/null)

if [ -z "$FUNC" ]; then
  echo "Error: function_name output not found. Has 'terraform apply' run yet?"
  exit 1
fi

echo "Fetching function master key for HTTP invocation..."
KEY=$(/opt/homebrew/bin/az functionapp keys list \
  --name "$FUNC" \
  --resource-group "$RG" \
  --query "masterKey" -o tsv)

URL="https://${HOST}/api/run?code=${KEY}"
echo ""
echo "Invoking: https://${HOST}/api/run"
echo ""

curl -fSs -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"trigger":"manual","source":"tf_run_report.sh"}'

echo ""
echo ""
echo "To watch the function logs (live tail):"
echo "  az webapp log tail --name $FUNC --resource-group $RG"
