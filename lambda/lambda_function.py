import boto3
import json
import urllib3
import os
from datetime import datetime

# Configuration from Terraform Environment Variables
DISCORD_WEBHOOK = os.environ.get('DISCORD_WEBHOOK_URL')
SSM_DOCUMENT = os.environ.get('SSM_DOCUMENT_NAME')
http = urllib3.PoolManager()

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    ssm = boto3.client('ssm')
    
    # 1. Parse Event Data for "Cause"
    # EventBridge sends the 'reason' string explaining why the alarm triggered
    detail = event.get('detail', {})
    state_reason = detail.get('state', {}).get('reason', 'N/A')
    
    # Calculate downtime duration using the event timestamp
    event_time_str = event.get('time')
    event_time = datetime.fromisoformat(event_time_str.replace('Z', '+00:00'))
    downtime_duration = int((datetime.now(event_time.tzinfo) - event_time).total_seconds())
    
    # Extract Instance ID from metrics dimensions
    metrics = detail.get('configuration', {}).get('metrics', [{}])
    instance_id = metrics[0].get('metricStat', {}).get('metric', {}).get('dimensions', {}).get('InstanceId', 'Unknown')

    # 2. Validation: Maintenance Check
    # Prevents continuous triggering and unnecessary costs during maintenance
    tags = ec2.describe_tags(Filters=[{'Name': 'resource-id', 'Values': [instance_id]}])['Tags']
    is_maintenance = any(t['Key'] == 'Maintenance' and t['Value'].lower() == 'true' for t in tags)

    if is_maintenance:
        send_discord(instance_id, "⚠️ **Maintenance Mode Detected**", 
                     f"**Reason:** {state_reason}\n**Action:** Automation skipped to avoid interference.", 16776960)
        return {"status": "skipped"}

    # 3. Remediation: Calling the SSM Document
    # Automates recovery within minutes of detection
    ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName=SSM_DOCUMENT
    )

    # 4. Notify Discord with the "Reason"
    description = (
        f"**Cause of Downtime:** `{state_reason}`\n"
        f"**Time Since Detection:** `{downtime_duration} seconds`\n"
        f"**Remediation:** Triggered `{SSM_DOCUMENT}` successfully."
    )
    send_discord(instance_id, "🚨 **Auto-Remediation Triggered**", description, 15158332)
    
    return {"status": "success"}

def send_discord(instance_id, title, description, color):
    if not DISCORD_WEBHOOK: return
    payload = {
        "username": "Cloud Janitor",
        "embeds": [{
            "title": title,
            "description": description,
            "color": color,
            "fields": [
                {"name": "Instance ID", "value": f"`{instance_id}`", "inline": True},
                {"name": "Region", "value": "`ap-southeast-1`", "inline": True}
            ],
            "timestamp": datetime.utcnow().isoformat()
        }]
    }
    encoded_data = json.dumps(payload).encode('utf-8')
    http.request('POST', DISCORD_WEBHOOK, body=encoded_data, headers={'Content-Type': 'application/json'})