# Runbook: Regional Failover & Recovery

This is the operational procedure to follow during an actual (or drill) regional outage — distinct from `docs/RESULTS.md`, which records what happened during the test run.

## 1. Detect (automated)

- Route 53 health check on the primary endpoint transitions to **Unhealthy** after `FailureThreshold` consecutive failed checks (default: 3 × 30s = ~90s to detect).
- A CloudWatch alarm (`primary-endpoint-unhealthy`, see `cloudformation/monitoring.yaml`) watches this health check and fires into the `dr-failover-alerts` SNS topic — both a human alert (email) and the automated responder below fire from the same event, no manual polling required.
- Manual check, if needed:
```bash
  aws route53 get-health-check-status --health-check-id $HEALTH_CHECK_ID
```
- Cross-check the primary region isn't just a transient blip — look at AWS Health Dashboard / Service Health status for the region before assuming a full regional event.

## 2. Confirm failover

- Route 53 automatically shifts traffic to the SECONDARY record once the primary health check fails — no manual DNS change needed.
- Verify propagation:
```bash
  dig +short $APP_RECORD_NAME
```
  Should return `$SECONDARY_IP` once TTL (60s) expires on resolvers.

## 3. Scale up the secondary (automated)

- The `automated-dr-responder` Lambda (`lambda/automated-failover/`) is subscribed to the same SNS topic and, on `ALARM` state, calls `autoscaling:SetDesiredCapacity` on the secondary region's ASG — moving it from Warm Standby size to full production capacity automatically. This is the step that makes Warm Standby different from a passive failover target, and it no longer waits on a human to run a CLI command mid-incident.
- Confirm it happened:
```bash
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $SECONDARY_ASG_NAME --region $SECONDARY_REGION
```
- If the Lambda's `SCALE_DOWN_ON_RECOVERY` env var is `false` (the default), it deliberately does *not* scale back down automatically when the alarm clears — see step 7, Failback, for why that's manual.

## 4. Restore data if needed

- If the secondary's replicated data isn't current enough, restore from the latest cross-region recovery point:
```bash
  ./scripts/06-restore-from-backup.sh <recovery-point-arn>
```
- Confirm restored data is within the RPO (5 minutes) by comparing the recovery point timestamp to the failure time.

## 5. Validate

- Smoke-test the application against the secondary region's endpoint.
- Confirm writes are landing correctly and downstream services (if any) are pointed at the right region.

## 6. Communicate

- Notify stakeholders that the system is running in the secondary region and note any known limitations (reduced capacity, read-only mode, etc.) until failback.

## 7. Failback (once primary is healthy again)

- Re-sync any data written to the secondary during the outage back to the primary.
- Manually shift Route 53 back to PRIMARY once confidence is high, rather than waiting for automatic re-failover, to control the timing.
- Scale the secondary back down to its normal Warm Standby footprint.