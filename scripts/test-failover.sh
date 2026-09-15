#!/usr/bin/env bash
# Stops the primary instance and times how long DNS takes to resolve to the secondary IP.
# Usage: ./05-test-failover.sh
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/../.env"

echo ">> Stopping primary instance $PRIMARY_INSTANCE_ID in $PRIMARY_REGION"
aws ec2 stop-instances --instance-ids "$PRIMARY_INSTANCE_ID" --region "$PRIMARY_REGION"

START=$(date +%s)
echo ">> Polling DNS for $APP_RECORD_NAME every 15s until it resolves to $SECONDARY_IP ..."
while true; do
  RESOLVED_IP=$(dig +short "$APP_RECORD_NAME" | tail -1)
  echo "   $(date +%H:%M:%S) resolved: ${RESOLVED_IP:-<none>}"
  if [ "$RESOLVED_IP" == "$SECONDARY_IP" ]; then
    END=$(date +%s)
    ELAPSED=$(( (END - START) / 60 ))
    echo ">> Failover complete. Observed failover time: ~${ELAPSED} minutes"
    break
  fi
  sleep 15
done

echo ">> Record this number in docs/RESULTS.md"