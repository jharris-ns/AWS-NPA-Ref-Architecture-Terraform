# ==============================================================================
# Input Variables
# ==============================================================================
# Variables allow users to customize the Terraform configuration without
# modifying the code. They're defined here and can be set via:
#
#   1. terraform.tfvars file (most common for persistent values)
#   2. Command line: terraform apply -var="publisher_name=my-pub"
#   3. Environment variables: export TF_VAR_publisher_name="my-pub"
#   4. Interactive prompt (if no default and not provided)
#
# Variable blocks support:
#   - description: Documents what the variable is for (shown in prompts/docs)
#   - type: Enforces the data type (string, number, bool, list, map, object)
#   - default: Value used if none provided (makes variable optional)
#   - sensitive: Hides value in logs/output (use for secrets)
#   - validation: Custom rules to validate input values
#
# Reference variables with: var.<name> (e.g., var.publisher_name)
# ==============================================================================

# ==============================================================================
# Provider Configuration Variables
# ==============================================================================

variable "netskope_server_url" {
  description = "Netskope API server URL (e.g., https://tenant.goskope.com/api/v2)"
  type        = string
  # No default - user must provide this value
}

variable "netskope_api_key" {
  description = "Netskope API key. Recommend setting via NETSKOPE_API_KEY env var"
  type        = string
  sensitive   = true # Marks as sensitive - won't show in logs or plan output
  # No default - user must provide this value
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1" # Default makes this optional
}

variable "aws_profile" {
  description = "AWS CLI profile name (optional)"
  type        = string
  default     = "" # Empty string means use default credential chain
}

# ==============================================================================
# VPC Configuration Variables
# ==============================================================================

variable "create_vpc" {
  description = "Create new VPC (true) or use existing (false)"
  type        = bool
  default     = true
  # Boolean variables are great for feature flags / conditional resources
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (used when create_vpc=true or for security group rules)"
  type        = string
  default     = "10.0.0.0/16"
  # CIDR notation: 10.0.0.0/16 = 10.0.0.0 to 10.0.255.255 (65,536 IPs)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (NAT Gateways)"
  type        = list(string) # List type allows multiple values
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
  # /24 = 256 IPs per subnet
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (Publishers)"
  type        = list(string)
  default     = ["10.0.2.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for subnets (auto-select if empty)"
  type        = list(string)
  default     = [] # Empty list triggers auto-selection in locals
}

variable "existing_vpc_id" {
  description = "Existing VPC ID (used when create_vpc=false)"
  type        = string
  default     = ""
}

variable "existing_private_subnet_ids" {
  description = "Existing private subnet IDs (used when create_vpc=false)"
  type        = list(string)
  default     = []
}

# ==============================================================================
# Publisher Configuration Variables
# ==============================================================================

variable "publisher_name" {
  description = "Base name for NPA publishers"
  type        = string
  # No default - user must provide this value

  # Validation blocks add custom rules beyond basic type checking
  # The condition must evaluate to true for the value to be accepted
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.publisher_name))
    error_message = "Publisher name must start with a letter and contain only alphanumeric characters and hyphens."
    # can() returns true if the expression succeeds, false if it errors
    # regex() matches the value against a regular expression pattern
  }
}

variable "publisher_ami_id" {
  description = "AMI ID for NPA publisher (auto-detect if empty)"
  type        = string
  default     = "" # Empty triggers auto-detection via data source
}

variable "publisher_instance_type" {
  description = "EC2 instance type for publishers"
  type        = string
  default     = "t3.large"

  # Restrict to known-good instance types for NPA publishers
  validation {
    condition     = contains(["t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"], var.publisher_instance_type)
    error_message = "Instance type must be one of: t3.medium, t3.large, t3.xlarge, t3.2xlarge, m5.large, m5.xlarge, m5.2xlarge."
    # contains(list, value) checks if the value is in the list
  }
}

variable "publisher_key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  # No default - user must provide an existing key pair name
  # Key pairs are created separately in AWS Console or via aws_key_pair resource
}

variable "publisher_count" {
  description = "Number of publisher instances to deploy"
  type        = number # Numeric type for counts
  default     = 2

  validation {
    condition     = var.publisher_count >= 1 && var.publisher_count <= 10
    error_message = "Publisher count must be between 1 and 10."
    # Using && for AND logic in the condition
  }
}

# ==============================================================================
# Monitoring Configuration Variables
# ==============================================================================

variable "enable_cloudwatch_monitoring" {
  description = "Install CloudWatch agent for memory/disk metrics (~$2.40/month per instance)"
  type        = bool
  default     = false
  # Cost note in description helps users make informed decisions
}

# ==============================================================================
# Tagging Variables
# ==============================================================================
# Tags are key-value metadata attached to AWS resources.
# They're essential for:
#   - Cost allocation and billing reports
#   - Resource organization and filtering
#   - Automation and policy enforcement
#   - Identifying resource ownership
#
# These tags are applied to ALL AWS resources via provider default_tags.
# Per-resource Name tags merge with these and take precedence on conflict.
# ==============================================================================

variable "tags" {
  description = "Common tags applied to all AWS resources via provider default_tags"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
  }
}
