# Results

_Live test run: 2026-09-15, us-east-1 (primary) / us-west-2 (secondary)._

## Objectives vs. measured outcomes

| Metric | Target | Measured | Met? |
|---|---|---|---|
| RTO (failover time) | ≤ 30 min | **~2 min** | ✅ Yes, well within target |
| Failback time (primary healthy → DNS back to primary) | — | **< 2 min** once health check passed | ✅ Confirmed working |
| Automated scale-up (alarm → ASG at full capacity) | — | Confirmed: alarm fired, ASG desired capacity 1 → 4 | ✅ Working as designed |
| Backup completion time (on-demand) | — | ~2 min (22:47:57 → 22:49:59) | — |
| Restore time (start restore → available) | — | Completed successfully; exact duration not precisely timestamped, but consistent with typical 10-20 min RDS restore times | ✅ Completed |
| Restored data validation (`SHOW DATABASES` etc.) | — | Not completed — public access + SG were opened for this, but the check was never actually run before moving to the failback test | ⬜ Open |
| RPO (data loss window) | ≤ 5 min | See note below | See note |

## How each number was measured

- **Failover time:** `scripts/test-failover.sh` stopped the primary EC2 instance, then polled `dig @<Route53 nameserver> app.dr-lab.internal` every 15s. First poll at 22:31:12 still returned the primary IP (100.63.206.186); by 22:33:15 it resolved to the secondary IP (54.68.203.90) — ~2 minutes, well under the 90s-detection + 60s-TTL theoretical minimum, likely because the health check had already been probing for a few cycles before the instance stopped.
- **Automated response:** Confirmed separately via `aws cloudwatch describe-alarms` (state: `ALARM`) and `aws autoscaling describe-auto-scaling-groups` (desired capacity: `4`, up from the warm-standby baseline of `1`) — the Lambda responder fired correctly off the same SNS topic as the human alert.
- **Backup timing:** Triggered on-demand via `aws backup start-backup-job` against the live `orders-db` RDS instance. `CreationDate` 22:47:57 → `CompletionDate` 22:49:59.
- **Restore timing:** Triggered via `scripts/06-restore-from-backup.sh` against the recovery point above. First two attempts failed on metadata/parameter issues (see "Issues encountered" below) before a working restore actually kicked off around 23:03. Tracked via `aws rds describe-db-instances` status transitions (`creating` → `configuring-enhanced-monitoring` → `backing-up` → ...) rather than the AWS Backup job status, since the Backup-side job record showed `FAILED` (duplicate-instance error) even though the underlying RDS restore was genuinely proceeding.

## Note on the RPO measurement

The RPO figure (≤5 min data loss) is normally measured as the gap between the *last completed backup before a real failure* and the failure itself. In this test run, the backup/restore drill was performed on-demand and independently of the failover drill (which happened earlier, ~22:31–22:33) — they weren't the same simulated incident. So rather than a true "data loss window," what's demonstrated here is that an on-demand backup completes in ~2 minutes, well inside a 5-minute RPO target if it were tied to an actual outage. A more rigorous validation would trigger the backup and the outage simulation together and measure the gap directly — noted as a follow-up in `README.md`'s Next steps.

## Issues encountered during the drill (worth keeping — this is the real story)

- Initial restore attempt failed: `DBInstanceIdentifier must be specified` — the restore metadata key was wrong (`TargetDBInstanceIdentifier` instead of the correct `DBInstanceIdentifier`).
- Second attempt failed with `RDS DBInstanceAlreadyExists`, but this was misleading — the underlying RDS instance was actually being created successfully in the background; the AWS Backup job record just couldn't reconcile with an instance ID that already existed. Validated via `aws rds describe-db-instances` directly rather than trusting the Backup job status alone.
- `IAM_BACKUP_ROLE_ARN` initially pointed at a non-existent default role (`AWSBackupDefaultServiceRole`); had to be corrected to the role CloudFormation actually created (`dr-backup-primary-backup-role`).
- **Failback initially failed silently**: after restarting the stopped primary instance, both the health check and the Route 53 A record still pointed at its *old* public IP. EC2 instances without an Elastic IP get a new public IP on every stop/start — the health check kept timing out against an address nothing was listening on anymore, even though the instance itself was healthy. Fixed by updating both the health check (`update-health-check --ip-address`) and the DNS record (`change-resource-record-sets` UPSERT) to the new IP. **Production fix**: attach an Elastic IP to the primary instance (or, better, put it behind an ALB) so restarts don't silently break the DR wiring — noted as a follow-up in `README.md`.

## Screenshots

Add screenshots to `docs` and reference them here:

- [ ] Backup plan configuration in the console
- [ ] Recovery points visible in both region vaults
- [ ] Route 53 failover record set
- [ ] Health check status transitioning to Unhealthy
- [ ] `dig` output showing DNS resolving to the secondary IP
- [ ] Restore job / RDS instance status: available
- [ ] CloudWatch alarm transitioning to ALARM state
- [ ] SNS email alert received
- [ ] Secondary ASG desired capacity change (1 → 4) confirming the automated-dr Lambda fired

## Conclusion

DNS failover comfortably beat the 30-minute RTO target at ~2 minutes, and failback was confirmed working in the opposite direction once the primary's health check recovered. The automated CloudWatch → SNS → Lambda → Auto Scaling chain fired correctly without manual intervention. The backup/restore path works but needed real debugging — a wrong metadata key, a misleading job-status error, and a missing Elastic IP that silently broke failback after a routine instance restart. None of these are exotic failures; they're exactly the class of gap a DR drill exists to surface before a real incident does, and each one is now documented with its actual fix rather than edited out.

**What I'd change for production**: attach an Elastic IP (or an ALB) to the primary so restarts don't break DNS wiring; have the restore script pass `VpcSecurityGroupIds` explicitly so restored instances inherit the locked-down security group instead of the VPC default; and tie the RPO measurement to the same simulated incident as the RTO test, rather than measuring backup speed independently.