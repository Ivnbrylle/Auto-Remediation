# AWS Cloud Janitor: Event-Driven Self-Healing Infrastructure

## Overview
This project demonstrates **Self-Healing Infrastructure** using a "Cloud Janitor" pattern. It is an automated remediation pipeline that detects service failures (specifically Nginx) on an Amazon Linux 2023 instance and fixes them without human intervention.

## Architecture
The system is built entirely as **Infrastructure as Code (IaC)** using Terraform and follows an event-driven design:

1. **Monitoring:** CloudWatch Alarms monitor the `StatusCheckFailed_Instance` metric.
2. **Detection:** If a service crash or instance failure occurs, the alarm enters the `ALARM` state.
3. **Trigger:** EventBridge intercepts the state change and initiates a remediation action.
4. **Remediation:** AWS Systems Manager (SSM) executes a custom Command Document to restart the Nginx service.
5. **Recovery:** Once the service is restored, CloudWatch automatically clears the alarm back to `OK`.

## Tech Stack
* **IaC:** Terraform
* **Cloud Provider:** AWS (Singapore Region - `ap-southeast-1`)
* **Services:** EC2, CloudWatch, EventBridge, Systems Manager (SSM), IAM
* **OS/Software:** Amazon Linux 2023, Nginx

## Key Outcomes
* **Reduced Downtime:** Automated the recovery process to occur within minutes of failure.
* **Zero-Touch Ops:** Eliminated the need for manual SSH/RDP access to fix service-level crashes.
* **Security First:** Implemented Least-Privilege IAM roles for EventBridge and SSM execution.

## Project Evidence
* **Systems Manager Success:** Verified automated execution of `RestartNginxService` with a `Success` status.
* **State Transition:** Captured the full lifecycle of a fault: `OK` -> `ALARM` -> `REMEDIATION` -> `OK`.

## Teardown
Infrastructure managed and destroyed via Terraform to optimize cost and resource management:
```bash
terraform destroy
