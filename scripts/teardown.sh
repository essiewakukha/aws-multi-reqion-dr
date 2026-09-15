#!/usr/bin/env bash
# Deletes every stack this project created, in reverse dependency order.
# Run this when you're done testing to stop being charged.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$DIR/.env"

echo ">> Deleting automated DR responder"
aws cloudformation delete-stack --stack-name dr-automated-response --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name dr-automated-response --region us-east-1

echo ">> Deleting monitoring stack"
aws cloudformation delete-stack --stack-name dr-monitoring --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name dr-monitoring --region us-east-1

echo ">> Deleting Route 53 failover stack"
aws cloudformation delete-stack --stack-name dr-route53-failover --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name dr-route53-failover --region us-east-1

echo ">> Deleting primary backup vault/plan"
aws cloudformation delete-stack --stack-name dr-backup-primary --region "$PRIMARY_REGION"
aws cloudformation wait stack-delete-complete --stack-name dr-backup-primary --region "$PRIMARY_REGION"

echo ">> Deleting secondary backup vault"
aws cloudformation delete-stack --stack-name dr-backup-secondary --region "$SECONDARY_REGION"
aws cloudformation wait stack-delete-complete --stack-name dr-backup-secondary --region "$SECONDARY_REGION"

echo ">> Deleting secondary bootstrap (web instance + ASG)"
aws cloudformation delete-stack --stack-name dr-bootstrap-secondary --region "$SECONDARY_REGION"
aws cloudformation wait stack-delete-complete --stack-name dr-bootstrap-secondary --region "$SECONDARY_REGION"

echo ">> Deleting primary bootstrap (web instance + RDS) - this can take a few minutes"
aws cloudformation delete-stack --stack-name dr-bootstrap-primary --region "$PRIMARY_REGION"
aws cloudformation wait stack-delete-complete --stack-name dr-bootstrap-primary --region "$PRIMARY_REGION"

echo ">> Emptying and removing the Lambda code bucket (optional - comment out to keep it)"
aws s3 rm "s3://$LAMBDA_CODE_BUCKET" --recursive --region "$PRIMARY_REGION" || true
aws s3 rb "s3://$LAMBDA_CODE_BUCKET" --region "$PRIMARY_REGION" || true

echo ">> Done. Double-check the console in both regions - AWS Backup recovery"
echo "   points created before deletion are NOT auto-deleted with the vault."
echo "   Delete them manually first if aws backup delete-backup-vault fails."