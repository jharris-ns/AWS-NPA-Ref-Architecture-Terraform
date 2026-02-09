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
#   2. Sends the registration command via SSM Run Command
#   3. Waits for the command to complete
#
# This approach is more reliable than user data because:
#   - Terraform waits for the instance and network to be fully ready
#   - Registration output is captured in SSM command history
#   - Failures are visible in the Terraform apply output
#   - No dependency on NAT Gateway timing during cloud-init
# ==============================================================================

resource "null_resource" "publisher_registration" {
  for_each = local.publishers

  triggers = {
    instance_id = aws_instance.publisher[each.key].id
    token_param = aws_ssm_parameter.publisher_token[each.key].name
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
  # Step 2: Register Publisher via SSM Run Command
  # --------------------------------------------------------------------------
  # Fetches the token locally from SSM Parameter Store, then passes it
  # directly to the instance via SSM Run Command. This avoids requiring
  # the AWS CLI on the publisher AMI.
  # --------------------------------------------------------------------------
  provisioner "local-exec" {
    command = <<-EOT
      echo "Fetching registration token from SSM Parameter Store..."
      TOKEN=$(aws ssm get-parameter \
        --name "${aws_ssm_parameter.publisher_token[each.key].name}" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region ${var.aws_region} \
        --profile ${var.aws_profile != "" ? var.aws_profile : "default"})

      echo "Registering publisher ${each.value.name} via SSM Run Command..."
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "${aws_instance.publisher[each.key].id}" \
        --document-name "AWS-RunShellScript" \
        --parameters commands="[\"/home/ubuntu/npa_publisher_wizard -token $TOKEN\"]" \
        --timeout-seconds 300 \
        --region ${var.aws_region} \
        --profile ${var.aws_profile != "" ? var.aws_profile : "default"} \
        --query "Command.CommandId" \
        --output text)

      echo "SSM Command ID: $COMMAND_ID"
      echo "Waiting for registration to complete..."

      aws ssm wait command-executed \
        --command-id "$COMMAND_ID" \
        --instance-id "${aws_instance.publisher[each.key].id}" \
        --region ${var.aws_region} \
        --profile ${var.aws_profile != "" ? var.aws_profile : "default"} 2>/dev/null || true

      STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "${aws_instance.publisher[each.key].id}" \
        --region ${var.aws_region} \
        --profile ${var.aws_profile != "" ? var.aws_profile : "default"} \
        --query "Status" \
        --output text)

      OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "${aws_instance.publisher[each.key].id}" \
        --region ${var.aws_region} \
        --profile ${var.aws_profile != "" ? var.aws_profile : "default"} \
        --query "StandardOutputContent" \
        --output text)

      echo "Registration output: $OUTPUT"

      if [ "$STATUS" != "Success" ]; then
        ERROR=$(aws ssm get-command-invocation \
          --command-id "$COMMAND_ID" \
          --instance-id "${aws_instance.publisher[each.key].id}" \
          --region ${var.aws_region} \
          --profile ${var.aws_profile != "" ? var.aws_profile : "default"} \
          --query "StandardErrorContent" \
          --output text)
        echo "ERROR: Registration failed with status $STATUS"
        echo "Error output: $ERROR"
        exit 1
      fi

      echo "Publisher ${each.value.name} registered successfully"
    EOT
  }
}
