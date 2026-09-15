#!/usr/bin/env bash
# Starts a restore job from the most recent recovery point in the primary vault.
# Adjust --resource-type and --metadata for your actual resource (RDS shown here).
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/../.env"

echo ">> Listing recovery points in $BACKUP_VAULT_NAME"
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$BACKUP_VAULT_NAME" \
  --region "$PRIMARY_REGION"

RECOVERY_POINT_ARN="${1:?Usage: $0 <recovery-point-arn>}"

echo ">> Starting restore job from $RECOVERY_POINT_ARN"
RESTORE_JSON=$(aws backup start-restore-job \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --metadata '{"DBInstanceClass":"db.t3.micro","DBSubnetGroupName":"my-subnet-group","MultiAZ":"false"}' \
  --iam-role-arn "$IAM_BACKUP_ROLE_ARN" \
  --resource-type RDS \
  --region "$PRIMARY_REGION")

RESTORE_JOB_ID=$(echo "$RESTORE_JSON" | grep -o '"RestoreJobId": "[^"]*"' | cut -d'"' -f4)
echo "   Restore job id: $RESTORE_JOB_ID"
echo ">> Poll status with:"
echo "   aws backup describe-restore-job --restore-job-id $RESTORE_JOB_ID --region \$PRIMARY_REGION"