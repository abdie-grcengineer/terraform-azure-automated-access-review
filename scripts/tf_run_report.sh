#!/bin/bash
# Manually trigger the access review Container App Job.
# Container App Jobs support on-demand starts via `az containerapp job start`,
# even when the trigger_type is Schedule. Useful for testing without waiting
# for the next scheduled run.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

if [ ! -d "$TERRAFORM_DIR/.terraform" ]; then
  echo "Error: $TERRAFORM_DIR is not initialized. Run 'terraform init' first."
  exit 1
fi

RG=$(terraform -chdir="$TERRAFORM_DIR" output -raw resource_group 2>/dev/null)
JOB=$(terraform -chdir="$TERRAFORM_DIR" output -raw container_app_job_name 2>/dev/null)

if [ -z "$JOB" ]; then
  echo "Error: container_app_job_name output not found. Has 'terraform apply' run yet?"
  exit 1
fi

echo "Starting Container App Job: $JOB"
echo ""

/opt/homebrew/bin/az containerapp job start \
  --name "$JOB" \
  --resource-group "$RG"

echo ""
echo "Job execution queued."
echo ""
echo "To watch the job logs:"
echo "  az containerapp job execution list --name $JOB --resource-group $RG --query \"[0].{name:name, status:properties.status, started:properties.startTime}\" -o table"
echo ""
echo "Or stream the latest execution's logs:"
echo "  az containerapp job logs show --name $JOB --resource-group $RG --container access-review --follow"
