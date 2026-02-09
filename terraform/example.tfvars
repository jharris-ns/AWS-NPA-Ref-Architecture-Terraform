

# ==============================================================================
# Example Terraform Variables File
# ==============================================================================
# This file shows all available variables with example values.
#
# HOW TO USE:
#   1. Copy this file: cp example.tfvars terraform.tfvars
#   2. Edit terraform.tfvars with your actual values
#   3. Run: terraform plan (it will automatically use terraform.tfvars)
#
# Alternatively, you can:
#   - Use a different filename: terraform plan -var-file="production.tfvars"
#   - Set variables via CLI: terraform plan -var="publisher_name=my-pub"
#   - Use environment variables: export TF_VAR_publisher_name="my-pub"
#
# SECURITY WARNING:
#   - NEVER commit terraform.tfvars to version control!
#   - It may contain sensitive values (API keys, etc.)
#   - The .gitignore file should exclude *.tfvars (except example.tfvars)
# ==============================================================================

# ------------------------------------------------------------------------------
# AWS Configuration
# ------------------------------------------------------------------------------

# AWS region where resources will be deployed.
# Used by: providers.tf (AWS provider region)
#          vpc.tf (VPC endpoint service names: com.amazonaws.${region}.ssm, etc.)
aws_region = "us-east-1"

# AWS CLI profile name (optional).
# Used by: providers.tf (AWS provider authentication)
# Leave empty to use default credential chain (env vars, instance profile, etc.)
aws_profile = ""

# ------------------------------------------------------------------------------
# Netskope Configuration
# ------------------------------------------------------------------------------
# SECURITY BEST PRACTICE: Set these via environment variables instead:
#   export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
#   export TF_VAR_netskope_api_key="your-api-key"

# Netskope API server URL.
# Used by: providers.tf (Netskope provider server_url)
# Format: https://{tenant}.goskope.com/api/v2
# netskope_server_url = "https://mytenant.goskope.com/api/v2"

# Netskope API key (sensitive).
# Used by: providers.tf (Netskope provider api_key)
# Generate in Netskope admin console: Settings > Tools > REST API v2
# netskope_api_key = ""  # DO NOT store API key in this file

# ------------------------------------------------------------------------------
# VPC Configuration
# ------------------------------------------------------------------------------

# Create new VPC (true) or use an existing one (false).
# Used by: locals.tf (resolves local.vpc_id and local.private_subnet_ids)
#          vpc.tf (conditional creation of VPC, subnets, IGW, NAT GWs, route
#                  tables, SSM VPC endpoints)
#          outputs.tf (conditional VPC/subnet/NAT outputs)
create_vpc = true

# CIDR block for the VPC.
# Used by: vpc.tf (aws_vpc CIDR block, SSM endpoint security group ingress)
#          security.tf (publisher security group egress rule)
# Only used when create_vpc = true (except security.tf which always uses it).
vpc_cidr = "10.0.0.0/16"

# CIDR blocks for public subnets (NAT Gateways are placed here).
# Used by: vpc.tf (aws_subnet.public CIDR blocks, controls the number of
#                  public subnets, EIPs, and NAT Gateways created)
# Only used when create_vpc = true.
public_subnet_cidrs = ["10.0.1.0/24", "10.0.3.0/24"]

# CIDR blocks for private subnets (Publishers are placed here).
# Used by: vpc.tf (aws_subnet.private CIDR blocks, controls the number of
#                  private subnets and route tables created)
# Only used when create_vpc = true.
private_subnet_cidrs = ["10.0.2.0/24", "10.0.4.0/24"]

# Availability Zones for subnets.
# Used by: locals.tf (resolves local.azs; empty = auto-select first 2 AZs)
# Only used when create_vpc = true.
availability_zones = []

# ---- EXISTING VPC CONFIGURATION ----
# Use these when create_vpc = false:
#
# existing_vpc_id — Used by: locals.tf (resolves local.vpc_id)
# existing_private_subnet_ids — Used by: locals.tf (resolves local.private_subnet_ids)
#
# create_vpc                  = false
# existing_vpc_id             = "vpc-0123456789abcdef0"
# existing_private_subnet_ids = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]
#
# Note: When using existing VPC, ensure:
#   - Private subnets have NAT Gateway routes for internet access
#   - VPC has DNS hostnames and DNS support enabled

# ------------------------------------------------------------------------------
# Publisher Configuration
# ------------------------------------------------------------------------------

# Base name for NPA publishers.
# Used by: locals.tf (generates the publisher map keys for for_each)
#          vpc.tf (Name tags on VPC, IGW, subnets, route tables, NAT GWs,
#                  EIPs, SSM endpoint SG, VPC endpoints)
#          security.tf (publisher security group name and Name tag)
#          iam.tf (IAM role name, instance profile name, role Name tag)
#          ssm.tf (SSM parameter path and Name tag, CloudWatch config group)
#          netskope.tf (Netskope publisher resource names)
# Requirements: Start with a letter, alphanumeric + hyphens only.
publisher_name = "npa-publisher-aws"

# AMI ID for the Netskope Publisher.
# Used by: locals.tf (resolves local.publisher_ami_id; empty = auto-detect)
#          netskope.tf (conditional data.aws_ami lookup when empty)
#          ec2_publisher.tf (aws_instance AMI via local.publisher_ami_id)
publisher_ami_id = ""

# EC2 instance type for publishers.
# Used by: ec2_publisher.tf (aws_instance.publisher instance_type)
# Allowed: t3.medium, t3.large, t3.xlarge, t3.2xlarge,
#          m5.large, m5.xlarge, m5.2xlarge
publisher_instance_type = "t3.large"

# EC2 key pair name for SSH access.
# Used by: ec2_publisher.tf (aws_instance.publisher key_name)
# Must be an existing key pair in the target region.
# For day-to-day access, prefer SSM Session Manager over SSH.
publisher_key_name = "my-key-pair"

# Number of publisher instances to deploy.
# Used by: locals.tf (range loop to build the publisher map for for_each)
# Min: 1, Max: 10. At least 2 recommended for HA (spread across AZs).
publisher_count = 2

# ------------------------------------------------------------------------------
# Monitoring Configuration
# ------------------------------------------------------------------------------

# Enable CloudWatch agent for memory/disk metrics.
# Used by: iam.tf (conditional CloudWatch agent IAM policy attachment,
#                  SSM parameter read policy)
#          ssm.tf (conditional CloudWatch config SSM parameter)
#          ec2_publisher.tf (passed to userdata template to install agent)
# Cost: ~$2.40/month per instance for custom metrics.
enable_cloudwatch_monitoring = false

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
# Applied to ALL AWS resources via provider default_tags (providers.tf).
# Per-resource Name tags merge with these and take precedence on conflicts.
# Add whatever your organization requires for cost allocation, ownership, etc.

tags = {
  ManagedBy   = "Terraform"
  Environment = "Production"
  Project     = "NPA-Publisher"
  CostCenter  = "IT-Operations"
  # Owner     = "security-team"
}