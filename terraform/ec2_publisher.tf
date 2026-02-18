# ==============================================================================
# EC2 Instances
# ==============================================================================
# EC2 (Elastic Compute Cloud) instances are virtual servers in AWS.
# This file creates the NPA Publisher instances.
#
# Each instance:
#   - Runs the Netskope Publisher AMI
#   - Is registered with Netskope via SSM Run Command after boot
#   - Optionally runs CloudWatch agent for monitoring
#   - Is distributed across availability zones for redundancy
# ==============================================================================

resource "aws_instance" "publisher" {
  for_each = local.publishers # Create instances from the publisher name map

  # --------------------------------------------------------------------------
  # Basic Instance Configuration
  # --------------------------------------------------------------------------
  ami           = local.publisher_ami_id      # AMI (Amazon Machine Image) to use
  instance_type = var.publisher_instance_type # Instance size (CPU, memory)
  key_name      = var.publisher_key_name      # SSH key pair for emergency access

  # --------------------------------------------------------------------------
  # IAM and Networking
  # --------------------------------------------------------------------------
  iam_instance_profile   = aws_iam_instance_profile.publisher.name # IAM role
  vpc_security_group_ids = [aws_security_group.publisher.id]       # Firewall rules
  monitoring             = true                                    # Detailed CloudWatch monitoring

  # Distribute instances across subnets (and thus AZs) using modulo
  subnet_id = local.private_subnet_ids[each.value.index % length(local.private_subnet_ids)]

  # --------------------------------------------------------------------------
  # Instance Metadata Service (IMDS) Configuration
  # --------------------------------------------------------------------------
  metadata_options {
    http_endpoint               = "enabled"  # Enable IMDS
    http_tokens                 = "required" # Require IMDSv2 (session tokens)
    http_put_response_hop_limit = 2          # Allow containers to access IMDS
    instance_metadata_tags      = "enabled"  # Make instance tags available via IMDS
  }

  # --------------------------------------------------------------------------
  # Root Volume (Boot Disk)
  # --------------------------------------------------------------------------
  root_block_device {
    volume_size = 30    # 30 GB
    volume_type = "gp3" # General purpose SSD (latest generation)
    encrypted   = true  # Encrypt the volume at rest
  }

  # --------------------------------------------------------------------------
  # User Data (Startup Script)
  # --------------------------------------------------------------------------
  # Minimal bootstrap — only CloudWatch agent if enabled.
  # Publisher registration is handled via SSM Run Command (see below).
  # --------------------------------------------------------------------------
  user_data = base64encode(templatefile("${path.module}/templates/userdata.tftpl", {
    enable_cloudwatch           = var.enable_cloudwatch_monitoring
    cloudwatch_config_parameter = var.enable_cloudwatch_monitoring ? aws_ssm_parameter.cloudwatch_config[0].name : ""
  }))

  tags = {
    Name = each.value.name
  }

  depends_on = [
    netskope_npa_publisher_token.this,
    aws_nat_gateway.this,
    aws_route_table_association.private,
  ]

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ==============================================================================
# SSM-Based Publisher Registration
# ==============================================================================
# After each EC2 instance launches, Terraform:
#   1. Polls SSM until the instance appears as "Online" (SSM agent ready)
#   2. Starts an SSM Automation execution that:
#      a. Fetches the registration token server-side from SSM Parameter Store
#      b. Runs the registration wizard on the instance via SSM Run Command
#   3. Polls the automation execution until it completes
#
# The registration token never leaves AWS — it is resolved by the automation
# document's aws:executeAwsApi step and passed directly to the instance.
# ==============================================================================

resource "null_resource" "publisher_registration" {
  for_each = local.publishers

  depends_on = [aws_iam_role_policy.ssm_automation]

  triggers = {
    instance_id     = aws_instance.publisher[each.key].id
    token_param     = aws_ssm_parameter.publisher_token[each.key].name
    ssm_doc_version = aws_ssm_document.publisher_registration.latest_version
  }

  # --------------------------------------------------------------------------
  # Step 1: Wait for Instance to be SSM-Managed
  # --------------------------------------------------------------------------
  # Polls aws ssm describe-instance-information until the instance shows
  # as "Online". This confirms the SSM agent is running and the instance
  # has network connectivity.
  # --------------------------------------------------------------------------
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for instance ${aws_instance.publisher[each.key].id} to be SSM-managed..."
      MAX_ATTEMPTS=40
      ATTEMPT=0
      while true; do
        ATTEMPT=$((ATTEMPT + 1))
        STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${aws_instance.publisher[each.key].id}" \
          --query "InstanceInformationList[0].PingStatus" \
          --output text \
          --region ${var.aws_region} \
          --profile ${var.aws_profile != "" ? var.aws_profile : "default"} 2>/dev/null || echo "None")

        if [ "$STATUS" = "Online" ]; then
          echo "Instance ${aws_instance.publisher[each.key].id} is SSM-managed and Online"
          break
        fi

        if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
          echo "ERROR: Instance ${aws_instance.publisher[each.key].id} not SSM-managed after $MAX_ATTEMPTS attempts"
          exit 1
        fi

        echo "  Attempt $ATTEMPT/$MAX_ATTEMPTS - Status: $STATUS - waiting 15s..."
        sleep 15
      done
    EOT
  }

  # --------------------------------------------------------------------------
  # Step 2: Register Publisher via SSM Automation
  # --------------------------------------------------------------------------
  # Starts an SSM Automation execution that:
  #   1. Reads the registration token server-side from SSM Parameter Store
  #   2. Runs the registration wizard on the instance via SSM Run Command
  #
  # The token never leaves AWS — it's resolved by the automation document's
  # aws:executeAwsApi step and passed directly to the instance.
  # --------------------------------------------------------------------------
  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting SSM Automation for publisher ${each.value.name}..."
      EXECUTION_ID=$(aws ssm start-automation-execution \
        --document-name "${aws_ssm_document.publisher_registration.name}" \
        --parameters "InstanceId=${aws_instance.publisher[each.key].id},TokenParameterName=${aws_ssm_parameter.publisher_token[each.key].name}" \
        --region ${var.aws_region} \
        --profile ${var.aws_profile != "" ? var.aws_profile : "default"} \
        --query "AutomationExecutionId" \
        --output text)

      echo "SSM Automation Execution ID: $EXECUTION_ID"
      echo "Waiting for registration to complete..."

      MAX_ATTEMPTS=40
      ATTEMPT=0
      while true; do
        ATTEMPT=$((ATTEMPT + 1))
        STATUS=$(aws ssm get-automation-execution \
          --automation-execution-id "$EXECUTION_ID" \
          --region ${var.aws_region} \
          --profile ${var.aws_profile != "" ? var.aws_profile : "default"} \
          --query "AutomationExecution.AutomationExecutionStatus" \
          --output text)

        if [ "$STATUS" = "Success" ]; then
          echo "Publisher ${each.value.name} registered successfully"
          break
        fi

        if [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ] || [ "$STATUS" = "TimedOut" ]; then
          FAILURE_MSG=$(aws ssm get-automation-execution \
            --automation-execution-id "$EXECUTION_ID" \
            --region ${var.aws_region} \
            --profile ${var.aws_profile != "" ? var.aws_profile : "default"} \
            --query "AutomationExecution.FailureMessage" \
            --output text)
          echo "ERROR: Registration automation $STATUS"
          echo "Failure message: $FAILURE_MSG"
          exit 1
        fi

        if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
          echo "ERROR: Registration automation did not complete after $MAX_ATTEMPTS attempts"
          exit 1
        fi

        echo "  Attempt $ATTEMPT/$MAX_ATTEMPTS - Status: $STATUS - waiting 15s..."
        sleep 15
      done
    EOT
  }
}
