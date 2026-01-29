# ==============================================================================
# EC2 Instances
# ==============================================================================
# EC2 (Elastic Compute Cloud) instances are virtual servers in AWS.
# This file creates the NPA Publisher instances.
#
# Each instance:
#   - Runs the Netskope Publisher AMI
#   - Registers with Netskope using the token from netskope.tf
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
  # each.value.index % length(...) cycles through the list: 0, 1, 0, 1, ...
  # This ensures instances are spread across AZs for high availability
  subnet_id = local.private_subnet_ids[each.value.index % length(local.private_subnet_ids)]

  # --------------------------------------------------------------------------
  # Instance Metadata Service (IMDS) Configuration
  # --------------------------------------------------------------------------
  # IMDS allows instances to retrieve metadata about themselves (instance ID,
  # IAM credentials, etc.) by querying a special IP address.
  #
  # IMDSv2 (http_tokens = "required") is more secure than IMDSv1:
  #   - Requires a session token for requests
  #   - Protects against SSRF attacks
  #   - AWS security best practice
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
  # The root_block_device is the instance's boot disk.
  #
  # gp3 is the latest general-purpose SSD type:
  #   - Better price/performance than gp2
  #   - Configurable IOPS and throughput
  #   - Encrypted for security
  # --------------------------------------------------------------------------
  root_block_device {
    volume_size = 30    # 30 GB
    volume_type = "gp3" # General purpose SSD (latest generation)
    encrypted   = true  # Encrypt the volume at rest
  }

  # --------------------------------------------------------------------------
  # User Data (Startup Script)
  # --------------------------------------------------------------------------
  # User data is a script that runs when the instance first boots.
  # It's used here to:
  #   1. Register the publisher with Netskope using the token
  #   2. Optionally install and configure CloudWatch agent
  #
  # base64encode(): User data must be base64-encoded
  # templatefile(): Reads a template file and substitutes variables
  #
  # The template receives:
  #   - registration_token: Unique token for this publisher
  #   - enable_cloudwatch: Whether to install CloudWatch agent
  #   - cloudwatch_config_parameter: SSM parameter name for agent config
  # --------------------------------------------------------------------------
  user_data = base64encode(templatefile("${path.module}/templates/userdata.tftpl", {
    registration_token          = netskope_npa_publisher_token.this[each.key].token
    enable_cloudwatch           = var.enable_cloudwatch_monitoring
    cloudwatch_config_parameter = var.enable_cloudwatch_monitoring ? aws_ssm_parameter.cloudwatch_config[0].name : ""
  }))

  # --------------------------------------------------------------------------
  # Tags
  # --------------------------------------------------------------------------
  # The Name tag is special in AWS - it's displayed in the EC2 console.
  # Same naming pattern as publishers: first uses base name, others numbered.
  # --------------------------------------------------------------------------
  tags = {
    Name = each.value.name
  }

  # --------------------------------------------------------------------------
  # Lifecycle Rules
  # --------------------------------------------------------------------------
  # The lifecycle block controls how Terraform handles resource changes.
  #
  # ignore_changes tells Terraform to NOT replace the instance if these
  # attributes change. This is important because:
  #   - ami: New AMIs are released regularly; we don't want auto-updates
  #   - user_data: Changes would destroy and recreate the instance
  #
  # Without this, changing the AMI or user data would replace all instances!
  # To update instances intentionally, use a different workflow (e.g., taint).
  # --------------------------------------------------------------------------
  # --------------------------------------------------------------------------
  # Explicit Dependency
  # --------------------------------------------------------------------------
  # Ensures EC2 instances are destroyed BEFORE Netskope publisher resources.
  # The Netskope API will reject publisher deletion if a connected instance
  # still exists. While the implicit dependency through user_data -> token ->
  # publisher should handle this, ignore_changes on user_data can cause
  # Terraform to lose track of that chain. This explicit dependency guarantees
  # correct destroy ordering.
  # --------------------------------------------------------------------------
  depends_on = [netskope_npa_publisher_token.this]

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
