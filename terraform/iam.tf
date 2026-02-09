# ==============================================================================
# IAM Roles and Policies
# ==============================================================================
# IAM (Identity and Access Management) controls WHO can do WHAT in AWS.
#
# Key concepts for EC2:
#   - IAM Role: A set of permissions that can be assumed by AWS services
#   - Instance Profile: A container for an IAM role that EC2 instances use
#   - Policy: A document defining specific permissions (allow/deny actions)
#
# Why use IAM roles with EC2?
#   - No hardcoded credentials on the instance
#   - Permissions can be changed without touching the instance
#   - Credentials are automatically rotated by AWS
#   - Follows the principle of least privilege
# ==============================================================================

# ------------------------------------------------------------------------------
# IAM Policy Document: EC2 Trust Policy
# ------------------------------------------------------------------------------
# A "trust policy" (assume_role_policy) defines WHO can use the role.
# This says: "The EC2 service can assume this role"
#
# data "aws_iam_policy_document" is a Terraform-native way to write IAM policies.
# It's more readable and less error-prone than writing JSON directly.
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow" # Allow (not Deny) this action

    # Principal = who is allowed to perform the action
    principals {
      type        = "Service"             # It's an AWS service (not a user/role)
      identifiers = ["ec2.amazonaws.com"] # Specifically, the EC2 service
    }

    # Action = what they're allowed to do
    actions = ["sts:AssumeRole"] # Assume (use) this role
  }
}

# ------------------------------------------------------------------------------
# IAM Role for Publishers
# ------------------------------------------------------------------------------
# The IAM role itself - a "container" for permissions.
# EC2 instances will assume this role to get the permissions attached to it.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "publisher" {
  name               = "${var.publisher_name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = { Name = "${var.publisher_name}-instance-role" }
}

# ------------------------------------------------------------------------------
# Instance Profile
# ------------------------------------------------------------------------------
# An instance profile is required to attach an IAM role to an EC2 instance.
# Think of it as a "wrapper" that EC2 understands.
#
# When launching EC2: you specify the instance profile, not the role directly.
# The instance profile contains a reference to the role.
# ------------------------------------------------------------------------------
resource "aws_iam_instance_profile" "publisher" {
  name = "${var.publisher_name}-instance-profile"
  role = aws_iam_role.publisher.name # Link to the role above
}

# ------------------------------------------------------------------------------
# SSM Managed Instance Core Policy
# ------------------------------------------------------------------------------
# AWS-managed policy that enables AWS Systems Manager (SSM) features:
#   - Session Manager: SSH-like access without opening port 22
#   - Run Command: Execute commands remotely
#   - Patch Manager: Automated patching
#
# aws_iam_role_policy_attachment attaches an existing policy to a role.
# "arn:aws:iam::aws:policy/..." are AWS-managed policies (maintained by AWS).
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.publisher.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------------
# CloudWatch Agent Policy (Conditional)
# ------------------------------------------------------------------------------
# Only attach if CloudWatch monitoring is enabled.
#
# count = var.enable_cloudwatch_monitoring ? 1 : 0
#   - If monitoring enabled: attach 1 policy
#   - If monitoring disabled: attach 0 (skip)
#
# This policy allows the CloudWatch agent to:
#   - Send custom metrics (memory, disk usage)
#   - Send logs to CloudWatch Logs
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  role       = aws_iam_role.publisher.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ------------------------------------------------------------------------------
# SSM Parameter Access Policy: Publisher Registration Tokens
# ------------------------------------------------------------------------------
# Allows instances to read their registration tokens from SSM Parameter Store.
# Uses GetParameter with WithDecryption for SecureString parameters.
# Scoped to only the /npa/publishers/* path for least privilege.
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "publisher_token_access" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      for param in aws_ssm_parameter.publisher_token : param.arn
    ]
  }
}

resource "aws_iam_role_policy" "publisher_token_access" {
  name   = "publisher-token-access"
  role   = aws_iam_role.publisher.id
  policy = data.aws_iam_policy_document.publisher_token_access.json
}

# ------------------------------------------------------------------------------
# SSM Parameter Access Policy: CloudWatch Config (Conditional)
# ------------------------------------------------------------------------------
# Custom policy to allow reading the CloudWatch agent configuration from
# SSM Parameter Store.
#
# Unlike the AWS-managed policies above, this is a custom policy that we
# define ourselves with specific, limited permissions.
#
# data "aws_iam_policy_document": Defines the policy in HCL (converted to JSON)
# aws_iam_role_policy: Creates an inline policy attached directly to the role
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "cloudwatch_config_access" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  statement {
    effect = "Allow"

    # Only allow reading (GetParameter), not writing
    actions = ["ssm:GetParameter"]

    # Only for this specific parameter (principle of least privilege)
    # The [0] is needed because the SSM parameter uses count
    resources = [aws_ssm_parameter.cloudwatch_config[0].arn]
  }
}

resource "aws_iam_role_policy" "cloudwatch_config_access" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name   = "cloudwatch-config-access"
  role   = aws_iam_role.publisher.id
  policy = data.aws_iam_policy_document.cloudwatch_config_access[0].json
}
