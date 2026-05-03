#!/bin/bash
# Deploy with the OPA policy gate.
# Four-step ritual: plan -> JSON export -> conftest gate -> apply saved plan.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
POLICY_DIR="$SCRIPT_DIR/../policy"

cd "$TERRAFORM_DIR"

echo "=== 1. Generating Terraform plan ==="
terraform plan -out=tfplan -input=false

echo ""
echo "=== 2. Exporting plan to JSON for policy evaluation ==="
terraform show -json tfplan > tfplan.json

echo ""
echo "=== 3. Running OPA/Conftest policy gate ==="
conftest test --policy "$POLICY_DIR" --all-namespaces tfplan.json

echo ""
echo "=== 4. All policies passed, applying plan ==="
terraform apply tfplan

echo ""
echo "=== Deploy complete ==="
