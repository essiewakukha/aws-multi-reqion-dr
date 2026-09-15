#!/usr/bin/env bash
# Tags-based resource selection: attaches production-tagged resources to the backup plan.
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/../.env"

sed -e "s#__IAM_BACKUP_ROLE_ARN__#$IAM_BACKUP_ROLE_ARN#g" \
    -e "s/__TAG_KEY__/$TAG_KEY/g" \
    -e "s/__TAG_VALUE__/$TAG_VALUE/g" \
    "$DIR/backup-selection.json.template" > "$DIR/backup-selection.json"

BACKUP_PLAN_ID=$(aws backup list-backup-plans \
  --query "BackupPlansList[?BackupPlanName=='DailyProdBackups'].BackupPlanId" \
  --output text \
  --region "$PRIMARY_REGION")

echo ">> Attaching selection to plan $BACKUP_PLAN_ID"
aws backup create-backup-selection \
  --backup-plan-id "$BACKUP_PLAN_ID" \
  --backup-selection file://"$DIR/backup-selection.json" \
  --region "$PRIMARY_REGION"

echo ">> Verify recovery points once a backup has run:"
echo "   aws backup list-recovery-points-by-backup-vault --backup-vault-name \$BACKUP_VAULT_NAME --region \$PRIMARY_REGION"
echo "   aws backup list-recovery-points-by-backup-vault --backup-vault-name \$SECONDARY_BACKUP_VAULT_NAME --region \$SECONDARY_REGION"