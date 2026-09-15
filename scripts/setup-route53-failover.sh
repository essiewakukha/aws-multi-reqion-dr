#!/usr/bin/env bash
# Creates hosted zone, health check on primary, and failover A records.
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/../.env"

echo ">> Creating hosted zone for $HOSTED_ZONE_NAME"
ZONE_JSON=$(aws route53 create-hosted-zone \
  --name "$HOSTED_ZONE_NAME" \
  --caller-reference "$(date +%s)" \
  --hosted-zone-config Comment="DR Lab zone",PrivateZone=false)
HOSTED_ZONE_ID=$(echo "$ZONE_JSON" | grep -o '"Id": "[^"]*"' | head -1 | cut -d'"' -f4)
echo "   Hosted zone id: $HOSTED_ZONE_ID"

sed -e "s/__PRIMARY_ENDPOINT__/$PRIMARY_ENDPOINT/g" \
    "$DIR/health-check.json.template" > "$DIR/health-check.json"

echo ">> Creating health check on primary endpoint"
HC_JSON=$(aws route53 create-health-check \
  --caller-reference "$(date +%s)" \
  --health-check-config file://"$DIR/health-check.json")
HEALTH_CHECK_ID=$(echo "$HC_JSON" | grep -o '"Id": "[^"]*"' | head -1 | cut -d'"' -f4)
echo "   Health check id: $HEALTH_CHECK_ID"

sed -e "s/__APP_RECORD_NAME__/$APP_RECORD_NAME/g" \
    -e "s/__PRIMARY_IP__/$PRIMARY_IP/g" \
    -e "s/__SECONDARY_IP__/$SECONDARY_IP/g" \
    -e "s/__HEALTH_CHECK_ID__/$HEALTH_CHECK_ID/g" \
    "$DIR/failover-records.json.template" > "$DIR/failover-records.json"

echo ">> Applying failover A records for $APP_RECORD_NAME"
aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file://"$DIR/failover-records.json"

echo ">> Save these for later scripts:"
echo "   HOSTED_ZONE_ID=$HOSTED_ZONE_ID"
echo "   HEALTH_CHECK_ID=$HEALTH_CHECK_ID"