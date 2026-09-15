#!/usr/bin/env bash
# Stops the primary instance and times how long the Route 53 record takes
# to reflect the secondary IP. Since this lab doesn't use a publicly
# delegated domain, we query the hosted zone's own nameserver directly
# with dig @<nameserver> - that's a legitimate way to validate the failover
# records switch correctly without owning a domain.
#
# Usage: ./05-test-failover.sh <nameserver>
#   e.g. ./05-test-failover.sh ns-123.awsdns-45.com
#   (get the nameserver list from the NAME_SERVERS output of
#   07-deploy-cloudformation.sh, or:
#   aws route53 get-hosted-zone --id $HEALTH_CHECK_ID --query DelegationSet.NameServers)
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/../.env"

NAMESERVER="${1:?Usage: $0 <nameserver, e.g. ns-123.awsdns-45.com>}"

echo ">> Stopping primary instance $PRIMARY_INSTANCE_ID in $PRIMARY_REGION"
aws ec2 stop-instances --instance-ids "$PRIMARY_INSTANCE_ID" --region "$PRIMARY_REGION"

START=$(date +%s)
echo ">> Polling dig @$NAMESERVER $APP_RECORD_NAME every 15s until it resolves to $SECONDARY_IP ..."
while true; do
  RESOLVED_IP=$(dig @"$NAMESERVER" +short "$APP_RECORD_NAME" | tail -1)
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
echo ">> Also check the CloudWatch alarm and secondary ASG desired capacity - the"
echo "   automated-dr Lambda should have scaled dr-secondary-web-asg by now:"
echo "   aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names \$SECONDARY_ASG_NAME --region \$SECONDARY_REGION"