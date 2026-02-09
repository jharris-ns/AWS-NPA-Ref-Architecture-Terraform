# ==============================================================================
# SSM Parameters
# ==============================================================================
# AWS Systems Manager (SSM) Parameter Store is a secure storage service for:
#   - Configuration data
#   - Secrets (with SecureString type)
#   - Application settings
#
# Benefits over hardcoding values:
#   - Centralized configuration management
#   - Version history and audit trail
#   - Fine-grained access control via IAM
#   - Can be referenced by multiple resources/instances
#
# The CloudWatch agent can fetch its configuration directly from Parameter Store,
# eliminating the need to bake config into AMIs or manage config files.
# ==============================================================================

# ------------------------------------------------------------------------------
# NPA Publisher Registration Tokens
# ------------------------------------------------------------------------------
# Stores each publisher's registration token in SSM Parameter Store as a
# SecureString. The EC2 instance fetches the token at boot via the AWS CLI
# instead of having it embedded directly in user data.
#
# Benefits over embedding tokens in user data:
#   - Tokens are encrypted at rest with KMS
#   - Not visible in EC2 instance metadata
#   - Access controlled via IAM
#   - Auditable via CloudTrail
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "publisher_token" {
  for_each = local.publishers

  name        = "/npa/publishers/${each.value.name}/registration-token"
  type        = "SecureString"
  description = "NPA Publisher registration token for ${each.value.name}"
  value       = netskope_npa_publisher_token.this[each.key].token

  tags = { Name = "${each.value.name}-registration-token" }
}

# ------------------------------------------------------------------------------
# CloudWatch Agent Configuration Parameter
# ------------------------------------------------------------------------------
# Stores the CloudWatch agent configuration in SSM Parameter Store.
# The agent fetches this config at startup to know what metrics to collect.
#
# count = var.enable_cloudwatch_monitoring ? 1 : 0
#   - Only create if CloudWatch monitoring is enabled
#
# Parameter Store supports three types:
#   - String: Plain text (used here)
#   - StringList: Comma-separated values
#   - SecureString: Encrypted with KMS (for secrets)
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudwatch_config" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name        = "/cloudwatch-config/${var.publisher_name}"
  type        = "String" # Plain text is fine for config (not secrets)
  description = "CloudWatch agent configuration for NPA Publisher monitoring"

  # jsonencode() converts HCL maps/lists to JSON strings
  # This is cleaner than writing raw JSON in a heredoc
  value = jsonencode({
    # Agent-level settings
    agent = {
      metrics_collection_interval = 60 # Collect metrics every 60 seconds
      run_as_user                 = "cwagent"
    }

    # Metrics configuration
    metrics = {
      namespace = "NPA/Publisher" # Custom namespace in CloudWatch

      # Dimensions added to every metric (for filtering/grouping)
      append_dimensions = {
        InstanceId     = "$${aws:InstanceId}" # EC2 instance ID
        PublisherGroup = var.publisher_name   # Group all publishers together
      }
      # Note: $${...} escapes the $ so Terraform doesn't interpret it
      # The CloudWatch agent will resolve ${aws:InstanceId} at runtime

      # Which metrics to collect
      metrics_collected = {
        # CPU metrics
        cpu = {
          measurement = [
            { name = "cpu_usage_idle", rename = "CPU_IDLE", unit = "Percent" },
            { name = "cpu_usage_iowait", rename = "CPU_IOWAIT", unit = "Percent" }
          ]
          metrics_collection_interval = 60
          resources                   = ["*"] # All CPUs
          totalcpu                    = false # Per-CPU metrics, not total
        }

        # Disk metrics
        disk = {
          measurement = [
            { name = "used_percent", rename = "DISK_USED", unit = "Percent" }
          ]
          metrics_collection_interval = 60
          resources                   = ["*"] # All mounted disks
        }

        # Memory metrics (not available by default in CloudWatch)
        mem = {
          measurement = [
            { name = "mem_used_percent", rename = "MEMORY_USED", unit = "Percent" }
          ]
          metrics_collection_interval = 60
        }

        # Swap metrics
        swap = {
          measurement = [
            { name = "swap_used_percent", rename = "SWAP_USED", unit = "Percent" }
          ]
          metrics_collection_interval = 60
        }
      }
    }
  })

  tags = { Name = "${var.publisher_name}-cloudwatch-config" }
}
