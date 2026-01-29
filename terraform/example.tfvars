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
# These settings control where and how AWS resources are created.

# AWS region where resources will be deployed
# Choose a region close to your users/applications for lower latency
aws_region = "us-east-1"

# AWS CLI profile name (optional)
# Leave empty to use default credentials from:
#   - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#   - IAM role (if running on EC2/ECS)
#   - Default profile in ~/.aws/credentials
aws_profile = "" # Leave empty to use default credentials

# ------------------------------------------------------------------------------
# Netskope Configuration
# ------------------------------------------------------------------------------
# These settings connect Terraform to your Netskope tenant.
#
# SECURITY BEST PRACTICE:
# Set these via environment variables instead of this file:
#   export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
#   export TF_VAR_netskope_api_key="your-api-key"
#
# This keeps secrets out of files that might accidentally be committed.

# Netskope API server URL
# Format: https://{tenant}.goskope.com/api/v2
# Find your tenant name in the Netskope admin console URL
# netskope_server_url = "https://mytenant.goskope.com/api/v2"

# Netskope API key
# Generate this in Netskope admin console: Settings > Tools > REST API v2
# NEVER store the actual API key in this file!
# netskope_api_key = ""  # DO NOT store API key in this file

# ------------------------------------------------------------------------------
# VPC Configuration
# ------------------------------------------------------------------------------
# Control whether to create a new VPC or use an existing one.

# Set to true to create a new VPC with all networking components
# Set to false to use an existing VPC (must provide existing_vpc_id)
create_vpc = true

# CIDR block for the VPC (only used when create_vpc = true)
# This defines the IP address range for the entire VPC
# /16 = 65,536 IP addresses (10.0.0.0 - 10.0.255.255)
vpc_cidr = "10.0.0.0/16"

# CIDR blocks for public subnets (NAT Gateways go here)
# These subnets have direct internet access via Internet Gateway
# /24 = 256 IP addresses per subnet
public_subnet_cidrs = ["10.0.1.0/24", "10.0.3.0/24"]

# CIDR blocks for private subnets (Publishers go here)
# These subnets access internet through NAT Gateways (outbound only)
private_subnet_cidrs = ["10.0.2.0/24", "10.0.4.0/24"]

# Availability Zones to use
# Empty list = auto-select first 2 available AZs in the region
# Explicit list = use specific AZs, e.g., ["us-east-1a", "us-east-1b"]
availability_zones = [] # Empty = auto-select

# ---- EXISTING VPC CONFIGURATION ----
# Use these settings when create_vpc = false
# Uncomment and fill in if using an existing VPC:
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
# These settings control the NPA Publisher instances.

# Base name for the publishers
# Used in AWS resource names and Netskope publisher names
# Requirements: Start with letter, alphanumeric + hyphens only
publisher_name = "npa-publisher-aws"

# AMI ID for the Netskope Publisher
# Empty = auto-detect latest from AWS Marketplace (recommended)
# Specific ID = use that exact AMI (useful for pinning versions)
publisher_ami_id = "" # Empty = auto-detect latest

# EC2 instance type
# Determines CPU, memory, and network performance
# Recommended minimum: t3.medium for light workloads
# Production recommendation: t3.large or m5.large for better performance
# Allowed values: t3.medium, t3.large, t3.xlarge, t3.2xlarge,
#                 m5.large, m5.xlarge, m5.2xlarge
publisher_instance_type = "t3.large"

# EC2 key pair name for SSH access
# Must be an existing key pair in the target region
# Create one in AWS Console: EC2 > Key Pairs > Create key pair
# This is for emergency access; prefer SSM Session Manager for normal access
publisher_key_name = "my-key-pair"

# Number of publisher instances to deploy
# Minimum: 1, Maximum: 10
# Recommendation: At least 2 for high availability (spread across AZs)
publisher_count = 2

# ------------------------------------------------------------------------------
# Monitoring Configuration
# ------------------------------------------------------------------------------
# Optional CloudWatch monitoring for additional metrics.

# Install CloudWatch agent for memory and disk metrics
# true = Install agent, collect memory/disk/CPU metrics
# false = Use only default EC2 metrics (CPU, network, disk I/O)
#
# Cost impact: ~$2.40/month per instance for custom metrics
# (Standard EC2 metrics are free)
enable_cloudwatch_monitoring = false # Adds ~$2.40/month per instance

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
# Tags are applied to all AWS resources for organization and cost tracking.

# Cost center for billing allocation
# Use your organization's cost center codes
cost_center = "IT-Operations"

# Project name for resource tracking
# Appears on all resources for easy identification
project = "NPA-Publisher"

# Environment type
# Allowed values: Production, Staging, Development, Test
environment = "Production"

# Additional custom tags (optional)
# Add any tags your organization requires
# These are merged with the default tags
additional_tags = {
  # Uncomment and customize:
  # Owner       = "security-team"
  # CostCode    = "12345"
  # Application = "Zero Trust Access"
}
