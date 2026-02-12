# 1. Dynamically fetch the latest Amazon Linux 2023 AMI for Singapore
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 2. IAM Role for EC2 to allow Systems Manager (SSM) access
resource "aws_iam_role" "ec2_ssm_role" {
  name = "auto_remediation_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "auto_remediation_profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# 3. The Web Server Instance
resource "aws_instance" "web_server" {
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  monitoring           = true # Enables 1-minute data intervals for faster detection

  user_data = <<-EOF
              #!/bin/bash
              dnf install -y nginx
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = {
    Name = "Cloud-Janitor-AutoFix"
  }
}

# 4. SSM Document: The actual repair instructions
resource "aws_ssm_document" "remediate_nginx" {
  name          = "RestartNginxService"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Restarts Nginx service"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "restartNginx"
      inputs = {
        runCommand = ["sudo systemctl restart nginx"]
      }
    }]
  })
}

# 5. CloudWatch Alarm: Monitoring Instance Health
resource "aws_cloudwatch_metric_alarm" "nginx_health_alarm" {
  alarm_name          = "NginxPortCheckFailed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "StatusCheckFailed_Instance"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"

  dimensions = {
    InstanceId = aws_instance.web_server.id
  }
}

# 6. EventBridge Rule: The "Link" between Alarm and Action
resource "aws_cloudwatch_event_rule" "remediation_rule" {
  name        = "trigger-nginx-remediation"
  description = "Trigger SSM when Nginx alarm goes off"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"],
    detail-type = ["CloudWatch Alarm State Change"],
    detail = {
      alarmName = ["NginxPortCheckFailed"], 
      state     = { value = ["ALARM"] }
    }
  })
}

# 7. EventBridge IAM Role & Target
resource "aws_iam_role" "eb_ssm_execution_role" {
  name = "eventbridge_ssm_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "eb_ssm_policy" {
  name = "eb_ssm_policy"
  role = aws_iam_role.eb_ssm_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "ssm:SendCommand"
      Effect   = "Allow"
      # Using wildcards for Resources ensures permission isn't blocked by ARN string mismatches
      Resource = [
        "arn:aws:ec2:ap-southeast-1:*:instance/*",
        "arn:aws:ssm:ap-southeast-1:*:document/*"
      ]
    }]
  })
}

resource "aws_cloudwatch_event_target" "ssm_target" {
  rule      = aws_cloudwatch_event_rule.remediation_rule.name
  # Use the dynamic ARN instead of a hardcoded string
  arn       = aws_ssm_document.remediate_nginx.arn 
  role_arn  = aws_iam_role.eb_ssm_execution_role.arn

  run_command_targets {
    key    = "InstanceIds"
    values = [aws_instance.web_server.id]
  }
}

# 8. Output for easy verification
output "instance_id" {
  value = aws_instance.web_server.id
}