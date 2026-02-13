# AWS Cloud Janitor: Event-Driven Self-Healing Infrastructure

## 📖 Overview
This project demonstrates **Self-Healing Infrastructure** using a "Cloud Janitor" pattern. It is an automated remediation pipeline that detects service failures (specifically Nginx) on an Amazon Linux 2023 instance and fixes them without human intervention.

## 🏗️ Architecture
The system is built entirely as **Infrastructure as Code (IaC)** using Terraform and follows an event-driven design:

1.  **Monitoring:** CloudWatch Alarms monitor instance health metrics.
2.  **Detection:** If a service crash occurs, the alarm enters the `ALARM` state.
3.  **Intelligence Layer (Lambda):** EventBridge triggers an **AWS Lambda function** which acts as the "Brain" of the Janitor.
    * **Validation:** Checks for a `Maintenance` tag on the EC2 instance to prevent automation during planned work.
    * **Logging:** Sends real-time "Auto-Logs" to **Discord** including the specific **Cause of Downtime** and calculated duration.
4.  **Remediation:** Upon successful validation, the Lambda triggers **AWS Systems Manager (SSM)** to execute a Command Document and restart Nginx.
5.  **Recovery:** CloudWatch automatically clears the alarm back to `OK` once the service is restored.



## 🛠️ Tech Stack
* **IaC:** Terraform
* **Cloud Provider:** AWS (Region: `ap-southeast-1`)
* **Services:** EC2, Lambda, CloudWatch, EventBridge, Systems Manager (SSM), IAM
* **Languages:** Python (Boto3), Bash, HCL
* **Integrations:** Discord Webhooks

## 🚀 Deployment & Management
A Bash script (`deploy.sh`) is provided to automate the infrastructure lifecycle and ensure the environment is correctly configured before deployment.

### Deploying the Janitor:
```bash
chmod +x deploy.sh
./deploy.sh apply
