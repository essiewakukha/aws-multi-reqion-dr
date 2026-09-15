"""
Automated DR responder.

Triggered by the dr-failover-alerts SNS topic (see cloudformation/monitoring.yaml).
When the primary-endpoint-unhealthy alarm fires (ALARM state), this scales the
secondary region's Auto Scaling Group up to production capacity - the "warm
standby -> full capacity" step from docs/RUNBOOK.md, done automatically instead
of by a human running a CLI command during an incident.

When the alarm clears (OK state), it optionally scales the secondary back down
once SCALE_DOWN_ON_RECOVERY=true is set - left off by default so a human
confirms it's safe to step the secondary back down (see RUNBOOK.md "Failback").
"""
import json
import os
import boto3

SECONDARY_REGION = os.environ["SECONDARY_REGION"]
ASG_NAME = os.environ["SECONDARY_ASG_NAME"]
SCALE_UP_DESIRED = int(os.environ.get("SCALE_UP_DESIRED_CAPACITY", "4"))
WARM_STANDBY_DESIRED = int(os.environ.get("WARM_STANDBY_DESIRED_CAPACITY", "1"))
SCALE_DOWN_ON_RECOVERY = os.environ.get("SCALE_DOWN_ON_RECOVERY", "false").lower() == "true"
NOTIFY_TOPIC_ARN = os.environ.get("ALERT_TOPIC_ARN")

autoscaling = boto3.client("autoscaling", region_name=SECONDARY_REGION)
sns = boto3.client("sns")


def handler(event, context):
    results = []
    for record in event.get("Records", []):
        message = json.loads(record["Sns"]["Message"])
        alarm_name = message.get("AlarmName")
        new_state = message.get("NewStateValue")
        results.append(_handle_state_change(alarm_name, new_state))
    return {"statusCode": 200, "body": json.dumps(results)}


def _handle_state_change(alarm_name, new_state):
    if new_state == "ALARM":
        return _scale_secondary(SCALE_UP_DESIRED, reason=f"{alarm_name} entered ALARM - scaling secondary to full capacity")
    if new_state == "OK" and SCALE_DOWN_ON_RECOVERY:
        return _scale_secondary(WARM_STANDBY_DESIRED, reason=f"{alarm_name} recovered - scaling secondary back to warm standby")
    return {"alarm": alarm_name, "state": new_state, "action": "none"}


def _scale_secondary(desired_capacity, reason):
    autoscaling.set_desired_capacity(
        AutoScalingGroupName=ASG_NAME,
        DesiredCapacity=desired_capacity,
        HonorCooldown=False,
    )
    _notify(f"[Automated DR] {reason}. {ASG_NAME} desired capacity set to {desired_capacity} in {SECONDARY_REGION}.")
    return {"asg": ASG_NAME, "desired_capacity": desired_capacity, "reason": reason}


def _notify(message):
    if not NOTIFY_TOPIC_ARN:
        return
    sns.publish(TopicArn=NOTIFY_TOPIC_ARN, Subject="Automated DR action taken", Message=message)