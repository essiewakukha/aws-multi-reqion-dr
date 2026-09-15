#!/usr/bin/env bash
#

set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/../.env"

echo ">> Listing recovery points in $BACKUP_VAULT_NAME"
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$BACKUP_VAULT_NAME" \
  --region "$PRIMARY_REGION"

RECOVERY_POINT_ARN="${1:?Usage: $0 <recovery-point-arn> [restored-db-instance-id]}"
RESTORED_DB_ID="${2:-orders-db-restored-test}"
SUBNET_GROUP="${RESTORE_DB_SUBNET_GROUP:?Set RESTORE_DB_SUBNET_GROUP in .env - see the aws cloudformation describe-stack-resources command in the header of this script}"

echo ">> Starting restore job from $RECOVERY_POINT_ARN into new instance $RESTORED_DB_ID"
RESTORE_JSON=$(aws backup start-restore-job \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --metadata "{\"DBInstanceClass\":\"db.t3.micro\",\"DBSubnetGroupName\":\"$SUBNET_GROUP\",\"MultiAZ\":\"false\",\"DBInstanceIdentifier\":\"$RESTORED_DB_ID\",\"PubliclyAccessible\":\"false\"}" \
  --iam-role-arn "$IAM_BACKUP_ROLE_ARN" \
  --resource-type RDS \
  --region "$PRIMARY_REGION")

RESTORE_JOB_ID=$(echo "$RESTORE_JSON" | grep -o '"RestoreJobId": "[^"]*"' | cut -d'"' -f4)
echo "   Restore job id: $RESTORE_JOB_ID"
echo ">> Poll status with:"
echo "   aws backup describe-restore-job --restore-job-id $RESTORE_JOB_ID --region \$PRIMARY_REGION --query Status"
echo ">> Once COMPLETED, remember to delete the restored instance when done validating:"
echo "   aws rds delete-db-instance --db-instance-identifier $RESTORED_DB_ID --skip-final-snapshot --region \$PRIMARY_REGION"