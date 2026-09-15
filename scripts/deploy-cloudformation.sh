#!/usr/bin/env bash
# Packages the automated-dr Lambda and deploys every CloudFormation stack in
# the correct order. Run from the repo root: ./scripts/07-deploy-cloudformation.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$DIR/.env"

LAMBDA_BUCKET="${LAMBDA_CODE_BUCKET:?Set LAMBDA_CODE_BUCKET in .env - an S3 bucket you own for Lambda deployment packages}"

echo ">> 1/6 Packaging automated-dr Lambda"
cd "$DIR/lambda/automated-failover"
zip -q -r automated-failover.zip lambda_function.py
aws s3 cp automated-failover.zip "s3://$LAMBDA_BUCKET/automated-failover.zip" --region "$PRIMARY_REGION"
cd "$DIR"

echo ">> 2/6 Deploying secondary-region backup vault"
aws cloudformation deploy \
  --template-file cloudformation/backup-secondary-vault.yaml \
  --stack-name dr-backup-secondary \
  --region "$SECONDARY_REGION" \
  --parameter-overrides BackupVaultName="$SECONDARY_BACKUP_VAULT_NAME" KmsKeyArn="$SECONDARY_KMS_KEY_ID"

SECONDARY_VAULT_ARN=$(aws cloudformation describe-stacks \
  --stack-name dr-backup-secondary --region "$SECONDARY_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='SecondaryVaultArn'].OutputValue" --output text)

echo ">> 3/6 Deploying primary-region backup vault + plan + selection"
aws cloudformation deploy \
  --template-file cloudformation/backup-primary.yaml \
  --stack-name dr-backup-primary \
  --region "$PRIMARY_REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides BackupVaultName="$BACKUP_VAULT_NAME" KmsKeyArn="$KMS_KEY_ID" \
    SecondaryVaultArn="$SECONDARY_VAULT_ARN" TagKey="$TAG_KEY" TagValue="$TAG_VALUE"

echo ">> 4/6 Deploying Route 53 failover"
aws cloudformation deploy \
  --template-file cloudformation/route53-failover.yaml \
  --stack-name dr-route53-failover \
  --parameter-overrides HostedZoneId="$HOSTED_ZONE_ID" AppRecordName="$APP_RECORD_NAME" \
    PrimaryEndpoint="$PRIMARY_ENDPOINT" PrimaryIp="$PRIMARY_IP" SecondaryIp="$SECONDARY_IP"

HEALTH_CHECK_ID=$(aws cloudformation describe-stacks \
  --stack-name dr-route53-failover \
  --query "Stacks[0].Outputs[?OutputKey=='HealthCheckId'].OutputValue" --output text)

echo ">> 5/6 Deploying CloudWatch alarm + dashboard + SNS topic"
aws cloudformation deploy \
  --template-file cloudformation/monitoring.yaml \
  --stack-name dr-monitoring \
  --region us-east-1 \
  --parameter-overrides HealthCheckId="$HEALTH_CHECK_ID" AlertEmail="${ALERT_EMAIL:-}"

ALERT_TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name dr-monitoring --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='DrAlertTopicArn'].OutputValue" --output text)

echo ">> 6/6 Deploying automated DR responder Lambda"
aws cloudformation deploy \
  --template-file cloudformation/automated-dr.yaml \
  --stack-name dr-automated-response \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AlertTopicArn="$ALERT_TOPIC_ARN" SecondaryRegion="$SECONDARY_REGION" \
    SecondaryAsgName="${SECONDARY_ASG_NAME:?Set SECONDARY_ASG_NAME in .env}" \
    LambdaCodeS3Bucket="$LAMBDA_BUCKET"

echo ">> Done. Health check: $HEALTH_CHECK_ID | Alert topic: $ALERT_TOPIC_ARN"