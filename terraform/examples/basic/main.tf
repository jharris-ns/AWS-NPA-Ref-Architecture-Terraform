# ==============================================================================
# Basic Example: NPA Publisher Deployment
# ==============================================================================
# This example demonstrates a minimal deployment of NPA Publishers.
#
# AWS I&A Standard: Every module must have at least one working example,
# conventionally named "basic". Examples should:
#   - Be fully functional and deployable
#   - Use sensible defaults
#   - Reference the parent module with source = "../../"
#   - Pin versions for external module dependencies
#
# Usage:
#   cd examples/basic
#   cp terraform.tfvars.example terraform.tfvars
#   # Edit terraform.tfvars with your values
#   terraform init
#   terraform plan
#   terraform apply
# ==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    netskope = {
      source = "netskopeoss/netskope"
    }
  }
}

# ------------------------------------------------------------------------------
# Provider Configuration
# ------------------------------------------------------------------------------
# In examples, providers ARE configured (unlike reusable modules).
# This allows the example to be deployed standalone.
# ------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

provider "netskope" {
  server_url = var.netskope_server_url
  api_key    = var.netskope_api_key
}

# ------------------------------------------------------------------------------
# Variables for Example
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "netskope_server_url" {
  description = "Netskope API server URL"
  type        = string
}

variable "netskope_api_key" {
  description = "Netskope API key"
  type        = string
  sensitive   = true
}

variable "publisher_name" {
  description = "Name for the NPA publisher"
  type        = string
  default     = "npa-publisher-example"
}

variable "publisher_key_name" {
  description = "EC2 key pair name"
  type        = string
}

# ------------------------------------------------------------------------------
# Module Invocation
# ------------------------------------------------------------------------------
# Reference the parent module using relative path.
# This is the standard pattern for examples within a module repository.
# ------------------------------------------------------------------------------

module "npa_publisher" {
  source = "../../"

  # Required: Netskope configuration
  netskope_server_url = var.netskope_server_url
  netskope_api_key    = var.netskope_api_key

  # Required: Publisher configuration
  publisher_name     = var.publisher_name
  publisher_key_name = var.publisher_key_name

  # Optional: Use defaults for everything else
  # Uncomment to override:
  # aws_region                   = var.aws_region
  # publisher_count              = 2
  # publisher_instance_type      = "t3.large"
  # create_vpc                   = true
  # vpc_cidr                     = "10.0.0.0/16"
  # enable_cloudwatch_monitoring = false
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "publisher_instance_ids" {
  description = "EC2 instance IDs"
  value       = module.npa_publisher.publisher_instance_ids
}

output "publisher_private_ips" {
  description = "Private IP addresses"
  value       = module.npa_publisher.publisher_private_ips
}

output "publisher_names" {
  description = "Netskope publisher names"
  value       = module.npa_publisher.publisher_names
}

output "vpc_id" {
  description = "VPC ID (if created)"
  value       = module.npa_publisher.vpc_id
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway public IPs for firewall whitelisting"
  value       = module.npa_publisher.nat_gateway_public_ips
}
