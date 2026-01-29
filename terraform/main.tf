# ==============================================================================
# Main Configuration
# ==============================================================================
# This is the primary entry point for the Terraform configuration.
#
# AWS I&A File Organization Standards:
#   - main.tf      : Primary resources and module calls (this file)
#   - versions.tf  : Terraform and provider version constraints
#   - providers.tf : Provider configuration blocks (root modules only)
#   - variables.tf : Input variable declarations
#   - outputs.tf   : Output value declarations
#   - locals.tf    : Local value definitions
#   - data.tf      : Data source definitions
#
# Service-specific files (vpc.tf, iam.tf, etc.) are used when a single
# service's configuration exceeds ~150 lines.
# ==============================================================================

# This module's resources are organized into service-specific files:
#   - vpc.tf      : VPC, subnets, NAT gateways, route tables
#   - security.tf : Security groups
#   - iam.tf      : IAM roles, policies, instance profiles
#   - netskope.tf : Netskope publishers, tokens, AMI lookup
#   - ec2.tf      : EC2 instances
#   - ssm.tf      : SSM parameters for CloudWatch config

# Note: For smaller modules, all resources would typically be in main.tf.
# We use separate files here because:
#   1. Each service has substantial configuration (>50 lines)
#   2. It improves navigability for educational purposes
#   3. It demonstrates AWS I&A patterns for larger modules
