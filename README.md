# AWS Cloud Janitor: Event-Driven Self-Healing Infrastructure

Automated remediation pipeline that detects and fixes service failures on AWS without human intervention.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Testing](#testing)
- [Security](#security)
- [Cost Considerations](#cost-considerations)
- [Cleanup](#cleanup)

## Overview

This project implements **Self-Healing Infrastructure** using a Cloud Janitor pattern. When Nginx fails on an EC2 instance, the system automatically detects the failure and remediates it—all within minutes.

### Key Features

- **Zero-Touch Recovery** - No manual SSH required to fix service crashes
- **Event-Driven Architecture** - Responds to failures in real-time
- **Discord Notifications** - Get alerts on remediation actions
- **Maintenance Mode** - Skip automation during planned maintenance
- **Infrastructure as Code** - Fully reproducible with Terraform

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌─────────────┐
│    EC2      │────▶│  CloudWatch  │────▶│ EventBridge │────▶│   Lambda    │
│   (Nginx)   │     │    Alarm     │     │    Rule     │     │   Function  │
└─────────────┘     └──────────────┘     └─────────────┘     └──────┬──────┘
       ▲                                                           │
       │                                                           ▼
       │            ┌──────────────┐                        ┌─────────────┐
       └────────────│     SSM      │◀───────────────────────│   Discord   │
                    │   Command    │                        │   Webhook   │
                    └──────────────┘                        └─────────────┘
```

**Flow:**

1. CloudWatch monitors EC2 `StatusCheckFailed_Instance` metric
2. On failure detection, alarm transitions to `ALARM` state
3. EventBridge captures the state change and triggers Lambda
4. Lambda validates maintenance mode and sends SSM command
5. SSM executes the remediation document to restart Nginx
6. Discord notification sent with cause and resolution details

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- AWS account with permissions for EC2, IAM, Lambda, CloudWatch, EventBridge, and SSM
- (Optional) Discord webhook URL for notifications

## Project Structure

```
Auto-Remediation/
├── main.tf                 # Terraform infrastructure configuration
├── lambda/
│   └── lambda_function.py  # Remediation orchestration logic
├── .gitignore
└── README.md
```

## Quick Start

### 1. Clone and Configure

```bash
cd Auto-Remediation
```

### 2. Set Discord Webhook (Optional)

Update the `DISCORD_WEBHOOK_URL` in `main.tf` or use a `terraform.tfvars` file:

```hcl
# In main.tf, update the environment variable
DISCORD_WEBHOOK_URL = "your-webhook-url"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Get the instance ID
terraform output instance_id

# Get the Lambda function name
terraform output lambda_function_name
```

## Configuration

### Environment Variables (Lambda)

| Variable              | Description                          |
| --------------------- | ------------------------------------ |
| `DISCORD_WEBHOOK_URL` | Discord webhook for notifications    |
| `SSM_DOCUMENT_NAME`   | Name of the SSM remediation document |

### EC2 Tags

| Tag           | Values         | Description                              |
| ------------- | -------------- | ---------------------------------------- |
| `Maintenance` | `true`/`false` | When `true`, skips automated remediation |

## How It Works

### Monitoring

The CloudWatch alarm monitors the `StatusCheckFailed_Instance` metric with:

- **Period:** 60 seconds
- **Evaluation:** 1 period
- **Threshold:** > 0 (any failure triggers alarm)

### Remediation Logic

The Lambda function (`lambda_function.py`):

1. **Parses** the EventBridge event to extract instance ID and failure reason
2. **Validates** maintenance mode using EC2 tags
3. **Executes** SSM command if not in maintenance
4. **Notifies** Discord with remediation details

### SSM Document

The `RestartNginxService` document executes:

```bash
sudo systemctl restart nginx
```

## Testing

### Simulate a Failure

SSH into the EC2 instance and stop Nginx:

```bash
# Connect via SSM Session Manager
aws ssm start-session --target <instance-id>

# Stop Nginx to trigger alarm
sudo systemctl stop nginx
```

### Test Maintenance Mode

Set the `Maintenance` tag to `true` to verify automation is skipped:

```bash
aws ec2 create-tags \
  --resources <instance-id> \
  --tags Key=Maintenance,Value=true
```

### Expected Results

- **Without Maintenance Mode:** Lambda triggers SSM, Nginx restarts, Discord notification sent
- **With Maintenance Mode:** Lambda skips remediation, warning notification sent

## Security

### IAM Least Privilege

| Role              | Permissions                                            |
| ----------------- | ------------------------------------------------------ |
| EC2 Instance Role | `AmazonSSMManagedInstanceCore` only                    |
| Lambda Role       | `ssm:SendCommand`, `ec2:DescribeTags`, CloudWatch Logs |

### Best Practices Implemented

- No SSH keys required (uses SSM for access)
- IAM roles scoped to minimum required permissions
- Secrets managed via environment variables

## Cost Considerations

### Resources Created

| Service    | Resource     | Estimated Cost     |
| ---------- | ------------ | ------------------ |
| EC2        | t3.micro     | ~$8/month          |
| Lambda     | Invocations  | Free tier eligible |
| CloudWatch | Alarm + Logs | ~$0.30/month       |
| SSM        | Commands     | Free               |

### Optimization Tips

- Use `terraform destroy` when not actively testing
- Enable detailed monitoring only when needed
- Consider Savings Plans for long-term use

## Cleanup

Destroy all infrastructure to stop incurring costs:

```bash
terraform destroy
```
