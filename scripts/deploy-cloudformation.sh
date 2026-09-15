#!/usr/bin/env bash
# Deploys the full DR stack in order, capturing each stack's outputs and
# feeding them into the next - you should not need to hand-copy any ARN,
# IP, or ID between steps. Run from the repo root:
#   ./scripts/07-deploy-cloudformation.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$DIR/.env"

out() { # out <stack-name> <region> <output-key>
  aws cloudformation describe-stacks --stack-name "$1" --region "$2" \
    --query "Stacks[0].Outputs[?OutputKey=='$3'].OutputValue" --output text
}

echo ">> 0a/7 Bootstrap: primary region web instance + RDS ($PRIMARY_REGION)"
aws cloudformation deploy \
  --template-file cloudformation/bootstrap-primary.yaml \
  --stack-name dr-bootstrap-primary \
  --region "$PRIMARY_REGION" \
  --parameter-overrides VpcId="$VPC_ID" WebSubnetId="$PRIMARY_WEB_SUBNET_ID" \
    DbSubnetIds="$PRIMARY_DB_SUBNET_IDS" DbMasterUsername="$DB_MASTER_USERNAME" \
    DbMasterPassword="$DB_MASTER_PASSWORD"

PRIMARY_IP=$(out dr-bootstrap-primary "$PRIMARY_REGION" PrimaryPublicIp)
PRIMARY_INSTANCE_ID=$(out dr-bootstrap-primary "$PRIMARY_REGION" PrimaryInstanceId)
RDS_ENDPOINT=$(out dr-bootstrap-primary "$PRIMARY_REGION" RdsEndpoint)
echo "   Primary IP: $PRIMARY_IP | Instance: $PRIMARY_INSTANCE_ID | RDS: $RDS_ENDPOINT"

echo ">> 0b/7 Bootstrap: secondary region DNS target + warm-standby ASG ($SECONDARY_REGION)"
aws cloudformation deploy \
  --template-file cloudformation/bootstrap-secondary.yaml \
  --stack-name dr-bootstrap-secondary \
  --region "$SECONDARY_REGION" \
  --parameter-overrides VpcId="$SECONDARY_VPC_ID" WebSubnetId="$SECONDARY_WEB_SUBNET_ID" \
    AsgSubnetIds="$SECONDARY_ASG_SUBNET_IDS"

SECONDARY_IP=$(out dr-bootstrap-secondary "$SECONDARY_REGION" SecondaryPublicIp)
SECONDARY_ASG_NAME=$(out dr-bootstrap-secondary "$SECONDARY_REGION" AsgName)
echo "   Secondary IP: $SECONDARY_IP | ASG: $SECONDARY_ASG_NAME"

echo ">> 1/7 Packaging automated-dr Lambda"
cd "$DIR/lambda/automated-failover"
rm -f automated-failover.zip
zip -q -r automated-failover.zip lambda_function.py
aws s3 mb "s3://$LAMBDA_CODE_BUCKET" --region "$PRIMARY_REGION" 2>/dev/null || true
aws s3 cp automated-failover.zip "s3://$LAMBDA_CODE_BUCKET/automated-failover.zip" --region "$PRIMARY_REGION"
cd "$DIR"

echo ">> 2/7 Deploying secondary-region backup vault"
aws cloudformation deploy \
  --template-file cloudformation/backup-secondary-vault.yaml \
  --stack-name dr-backup-secondary \
  --region "$SECONDARY_REGION" \
  --parameter-overrides BackupVaultName="$SECONDARY_BACKUP_VAULT_NAME"

SECONDARY_VAULT_ARN=$(out dr-backup-secondary "$SECONDARY_REGION" SecondaryVaultArn)

echo ">> 3/7 Deploying primary-region backup vault + plan + selection"
aws cloudformation deploy \
  --template-file cloudformation/backup-primary.yaml \
  --stack-name dr-backup-primary \
  --region "$PRIMARY_REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides BackupVaultName="$BACKUP_VAULT_NAME" \
    SecondaryVaultArn="$SECONDARY_VAULT_ARN" TagKey="$TAG_KEY" TagValue="$TAG_VALUE"

echo ">> 4/7 Deploying Route 53 hosted zone + failover records"
aws cloudformation deploy \
  --template-file cloudformation/route53-failover.yaml \
  --stack-name dr-route53-failover \
  --region us-east-1 \
  --parameter-overrides ZoneName="$ZONE_NAME" AppRecordName="$APP_RECORD_NAME" \
    PrimaryIp="$PRIMARY_IP" SecondaryIp="$SECONDARY_IP"

HEALTH_CHECK_ID=$(out dr-route53-failover us-east-1 HealthCheckId)
NAME_SERVERS=$(out dr-route53-failover us-east-1 NameServers)

echo ">> 5/7 Deploying CloudWatch alarm + dashboard + SNS topic"
aws cloudformation deploy \
  --template-file cloudformation/monitoring.yaml \
  --stack-name dr-monitoring \
  --region us-east-1 \
  --parameter-overrides HealthCheckId="$HEALTH_CHECK_ID" AlertEmail="${ALERT_EMAIL:-}"

ALERT_TOPIC_ARN=$(out dr-monitoring us-east-1 DrAlertTopicArn)

echo ">> 6/7 Deploying automated DR responder Lambda"
aws cloudformation deploy \
  --template-file cloudformation/automated-dr.yaml \
  --stack-name dr-automated-response \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AlertTopicArn="$ALERT_TOPIC_ARN" SecondaryRegion="$SECONDARY_REGION" \
    SecondaryAsgName="$SECONDARY_ASG_NAME" LambdaCodeS3Bucket="$LAMBDA_CODE_BUCKET"

cat >> "$DIR/.env" << ENV_EOF

# --- Auto-populated by deploy-cloudformation.sh on $(date) ---
PRIMARY_IP=$PRIMARY_IP
PRIMARY_INSTANCE_ID=$PRIMARY_INSTANCE_ID
SECONDARY_IP=$SECONDARY_IP
SECONDARY_ASG_NAME=$SECONDARY_ASG_NAME
HEALTH_CHECK_ID=$HEALTH_CHECK_ID
RDS_ENDPOINT=$RDS_ENDPOINT
ENV_EOF

echo ">> 7/7 Done."
echo "   Primary IP:        $PRIMARY_IP"
echo "   Secondary IP:      $SECONDARY_IP"
echo "   Health check ID:   $HEALTH_CHECK_ID"
echo "   Alert topic:       $ALERT_TOPIC_ARN"
echo "   Route 53 nameservers (use one of these with dig): $NAME_SERVERS"
echo ""
echo "   Test resolution:   dig @<a-nameserver-above> $APP_RECORD_NAME"
echo "   (values also appended to .env for use by scripts/05-test-failover.sh)"