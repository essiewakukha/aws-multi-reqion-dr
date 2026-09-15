#!/usr/bin/env bash
# Creates the primary and secondary KMS-encrypted AWS Backup vaults.
set -euo pipefail
source "$(dirname "$0")/../.env"

echo ">> Creating primary backup vault ($BACKUP_VAULT_NAME) in $PRIMARY_REGION"
aws backup create-backup-vault \
  --backup-vault-name "$BACKUP_VAULT_NAME" \
  --encryption-key-id "$KMS_KEY_ID" \
  --region "$PRIMARY_REGION"

echo ">> Creating secondary backup vault ($SECONDARY_BACKUP_VAULT_NAME) in $SECONDARY_REGION"
aws backup create-backup-vault \
  --backup-vault-name "$SECONDARY_BACKUP_VAULT_NAME" \
  --encryption-key-id "$KMS_KEY_ID" \
  --region "$SECONDARY_REGION"

echo ">> Done. Verify with:"
echo "   aws backup list-backup-vaults --region \$PRIMARY_REGION"