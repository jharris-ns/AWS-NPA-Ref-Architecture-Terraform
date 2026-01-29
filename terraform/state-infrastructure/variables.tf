# ==============================================================================
# State Infrastructure Variables
# ==============================================================================
# These variables configure the Terraform state storage infrastructure.
# ==============================================================================

variable "aws_region" {
  description = "AWS region for state infrastructure"
  type        = string
  default     = "us-east-1"
  # Choose a region close to your team for lower latency
  # State operations (read/write) happen frequently during Terraform runs
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "npa-publisher"
  # This prefix is used in all resource names:
  #   - S3 bucket: {project_name}-terraform-state-{account_id}
  #   - DynamoDB table: {project_name}-terraform-lock
  #   - KMS key alias: alias/{project_name}-terraform-state
}

variable "terraform_admin_role_arns" {
  description = "List of IAM role/user ARNs allowed to access Terraform state"
  type        = list(string)
  # No default - you MUST specify who can access state
  #
  # Examples:
  #   - IAM role: "arn:aws:iam::123456789012:role/TerraformAdmin"
  #   - IAM user: "arn:aws:iam::123456789012:user/terraform-user"
  #   - SSO role: "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_AdministratorAccess_abc123"
  #
  # SECURITY: Only include principals that NEED access to Terraform state.
  # State contains sensitive data including resource configurations and
  # potentially secrets stored in resource attributes.
}
