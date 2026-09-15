#!/usr/bin/env bash
# Renders backup-plan.json from the template and creates the backup plan.
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/../.env"

sed -e "s/__BACKUP_VAULT_NAME__/$BACKUP_VAULT_NAME/g" \
    -e "s/__SECONDARY_REGION__/$SECONDARY_REGION/g" \
    -e "s/__AWS_ACCOUNT_ID__/$AWS_ACCOUNT_ID/g" \
    -e "s/__SECONDARY_BACKUP_VAULT_NAME__/$SECONDARY_BACKUP_VAULT_NAME/g" \
    "$DIR/backup-plan.json.template" > "$DIR/backup-plan.json"

echo ">> Creating backup plan DailyProdBackups in $PRIMARY_REGION"
aws backup create-backup-plan \
  --backup-plan file://"$DIR/backup-plan.json" \
  --region "$PRIMARY_REGION"

echo ">> Done. List plans with:"
echo "   aws backup list-backup-plans --region \$PRIMARY_REGION"