# Design Decisions

## Workload

RDS MySQL database powering an orders service.

## Recovery objectives

- **RTO: 30 minutes** — the business can tolerate up to 30 minutes of downtime during a regional outage before it materially affects order processing.
- **RPO: 5 minutes** — losing more than 5 minutes of transaction data is unacceptable.

## DR pattern comparison

| Pattern | Downtime | Data loss | Cost | Fits our RTO/RPO? |
|---|---|---|---|---|
| Backup & Restore | Hours | Depends on backup frequency | $ | No — restore + provisioning time alone likely exceeds 30 min |
| **Warm Standby (chosen)** | Minutes | Near-continuous replication | $$ | Yes |
| Pilot Light | ~30–60 min (scale-up time) | Continuous | $$ | Borderline — scale-up risk |
| Multi-Site Active-Active | Seconds | Near-zero | $$$$ | Overkill for this workload's tolerance |

## Why Warm Standby

A continuously running, scaled-down environment in the secondary region means the database is already replicated and the compute layer just needs to scale up — not boot from cold. This comfortably fits a 30-minute RTO without the cost of running full-scale infrastructure in both regions simultaneously, which isn't justified by a 5-minute RPO tolerance.

## Trade-offs accepted

- Secondary region runs smaller instance sizes day-to-day, scaled up only during failover — cost savings vs. Active-Active, at the price of a short scale-up delay.
- DNS TTL set to 60 seconds to keep failover propagation fast, at the cost of slightly higher DNS query volume/cost.