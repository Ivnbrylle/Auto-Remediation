# --- 1. PROVIDER & DATA SOURCES ---
provider "aws" {
  region = "ap-southeast-1" # Singapore
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Packagae the Python code for Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/janitor_lambda.zip"
}

# --- 2. IAM ROLES ---

# Role for EC2 (Allows SSM to manage the instance)
resource "aws_iam_role" "ec2_ssm_role" {
  name = "cloud_janitor_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cloud_janitor_profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# Role for Lambda (Allows logging, reading tags, and triggering SSM)
resource "aws_iam_role" "lambda_role" {
  name = "cloud_janitor_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_janitor_permissions"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { 
        Action   = ["ssm:SendCommand", "ec2:DescribeTags"], 
        Effect   = "Allow", 
        Resource = "*" 
      },
      { 
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], 
        Effect   = "Allow", 
        Resource = "arn:aws:logs:*:*:*" 
      }
    ]
  })
}

# --- 3. INFRASTRUCTURE ---

resource "aws_instance" "web_server" {
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  monitoring           = true

  user_data = <<-EOF
              #!/bin/bash
              dnf install -y nginx
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = {
    Name        = "Cloud-Janitor-AutoFix"
    Maintenance = "false" # Toggle this to "true" to test automation validation
  }
}

resource "aws_ssm_document" "remediate_nginx" {
  name          = "RestartNginxService"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Restarts Nginx service"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "restartNginx"
      inputs = { runCommand = ["sudo systemctl restart nginx"] }
    }]
  })
}

# --- 4. MONITORING & AUTOMATION ---

resource "aws_cloudwatch_metric_alarm" "nginx_health_alarm" {
  alarm_name          = "NginxPortCheckFailed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "StatusCheckFailed_Instance"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  dimensions          = { InstanceId = aws_instance.web_server.id }
}

resource "aws_cloudwatch_event_rule" "remediation_rule" {
  name        = "trigger-nginx-remediation"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"],
    detail-type = ["CloudWatch Alarm State Change"],
    detail = {
      alarmName = ["NginxPortCheckFailed"], 
      state     = { value = ["ALARM"] }
    }
  })
}

resource "aws_lambda_function" "janitor_brain" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "CloudJanitor_Remediation_Brain"
  timeout          = 30  # Increase this to 30 seconds
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1471739768474697851/TjHI8UOVgyfSOOpfdKl378ZiMdwTENBQshKvyYr17gRWVhrdrLHlsmMNp6ylnbyz56fj"
      SSM_DOCUMENT_NAME   = aws_ssm_document.remediate_nginx.name
    }
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.remediation_rule.name
  target_id = "TriggerJanitorLambda"
  arn       = aws_lambda_function.janitor_brain.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.janitor_brain.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.remediation_rule.arn
}

# --- 5. OUTPUTS ---
output "instance_id" {
  value = aws_instance.web_server.id
}

output "lambda_function_name" {
  value = aws_lambda_function.janitor_brain.function_name
}