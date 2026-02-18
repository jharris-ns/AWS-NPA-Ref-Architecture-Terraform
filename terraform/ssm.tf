# ==============================================================================
# SSM Parameters and Automation Documents
# ==============================================================================
# AWS Systems Manager (SSM) resources:
#
# Parameter Store — secure storage for configuration and secrets:
#   - Registration tokens (SecureString, encrypted with KMS)
#   - CloudWatch agent configuration (String)
#
# Automation Documents — server-side orchestration for publisher registration:
#   - Fetches the token via aws:executeAwsApi (never leaves AWS)
#   - Runs the registration command on the instance via aws:runCommand
# ==============================================================================

# ------------------------------------------------------------------------------
# NPA Publisher Registration Tokens
# ------------------------------------------------------------------------------
# Stores each publisher's registration token in SSM Parameter Store as a
# SecureString. The SSM Automation Document reads these tokens server-side
# during publisher registration (see aws_ssm_document.publisher_registration).
#
# Benefits:
#   - Tokens are encrypted at rest with KMS
#   - Not visible in EC2 instance metadata or operator workstations
#   - Access controlled via IAM (only the SSM automation role can read them)
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

# ------------------------------------------------------------------------------
# SSM Automation Document: Publisher Registration
# ------------------------------------------------------------------------------
# Orchestrates publisher registration entirely server-side:
#   1. getToken      — aws:executeAwsApi reads the SecureString token from
#                      SSM Parameter Store (token never leaves AWS)
#   2. registerPublisher — aws:runCommand executes the registration wizard
#                          on the target instance with the resolved token
#
# The document assumes the ssm_automation IAM role (see iam.tf) which has
# permission to read tokens and send commands to publisher instances.
# ------------------------------------------------------------------------------
resource "aws_ssm_document" "publisher_registration" {
  name            = "${var.publisher_name}-publisher-registration"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Register an NPA Publisher instance with Netskope using a token from SSM Parameter Store"
    assumeRole    = aws_iam_role.ssm_automation.arn

    parameters = {
      InstanceId = {
        type        = "String"
        description = "EC2 instance ID of the publisher to register"
      }
      TokenParameterName = {
        type        = "String"
        description = "SSM Parameter Store name containing the registration token"
      }
    }

    mainSteps = [
      {
        name   = "getToken"
        action = "aws:executeAwsApi"
        inputs = {
          Service        = "ssm"
          Api            = "GetParameter"
          Name           = "{{ TokenParameterName }}"
          WithDecryption = true
        }
        outputs = [
          {
            Name     = "token"
            Selector = "$.Parameter.Value"
            Type     = "String"
          }
        ]
      },
      {
        name   = "registerPublisher"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds  = ["{{ InstanceId }}"]
          Parameters = {
            commands = ["/home/ubuntu/npa_publisher_wizard -token {{ getToken.token }}"]
          }
          TimeoutSeconds = 300
        }
      }
    ]
  })

  tags = { Name = "${var.publisher_name}-publisher-registration" }
}
