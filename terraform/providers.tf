# ==============================================================================
# Provider Configuration
# ==============================================================================
# Provider blocks configure how Terraform authenticates with external services.
# This file should only exist in ROOT modules (not reusable modules).
#
# AWS I&A Standard: Reusable modules must NOT contain provider blocks.
# Consumers of modules should configure providers in their root module.
# ==============================================================================

# ------------------------------------------------------------------------------
# Netskope Provider
# ------------------------------------------------------------------------------
# Authenticates with the Netskope API for publisher management.
#
# SECURITY: Set credentials via environment variables:
#   export TF_VAR_netskope_api_key="your-api-key"
# ------------------------------------------------------------------------------
provider "netskope" {
  server_url = var.netskope_server_url
  api_key    = var.netskope_api_key
}

# ------------------------------------------------------------------------------
# AWS Provider
# ------------------------------------------------------------------------------
# Authenticates with AWS for infrastructure provisioning.
#
# Authentication precedence:
#   1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#   2. Shared credentials file (~/.aws/credentials)
#   3. IAM instance profile (when running on EC2/ECS)
#
# default_tags: Applied to ALL resources created by this provider.
# This ensures consistent tagging without repetition in each resource.
# ------------------------------------------------------------------------------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        CostCenter  = var.cost_center
        ManagedBy   = "Terraform"
      },
      var.additional_tags
    )
  }
}
