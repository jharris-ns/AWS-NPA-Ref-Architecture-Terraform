# ==============================================================================
# Netskope NPA Publisher Resources
# ==============================================================================
# This file uses the Netskope Terraform provider to create and manage
# NPA (Network Private Access) Publishers in your Netskope tenant.
#
# NPA Publishers are software components that:
#   - Run inside your network (on EC2 instances in this case)
#   - Establish outbound connections to Netskope's cloud
#   - Proxy traffic from remote users to internal applications
#   - Enable Zero Trust Network Access (ZTNA)
#
# The workflow:
#   1. Create a publisher in Netskope (netskope_npa_publisher)
#   2. Generate a registration token (netskope_npa_publisher_token)
#   3. Use the token during EC2 instance startup to register the publisher
#   4. Publisher connects to Netskope and becomes available for app access
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Source: Netskope Publisher AMI
# ------------------------------------------------------------------------------
# Data sources fetch information from providers WITHOUT creating resources.
# They're read-only queries that return existing data.
#
# This data source finds the latest Netskope Publisher AMI in AWS Marketplace.
#
# count = var.publisher_ami_id == "" ? 1 : 0
#   - This is a conditional: if no AMI ID is provided, create 1 data source
#   - If an AMI ID IS provided, create 0 (skip the lookup entirely)
#   - This is a common pattern to make resources/data sources optional
#
# most_recent = true: If multiple AMIs match, use the newest one
# owners: Only search AMIs from AWS Marketplace (trusted source)
# filter: Search criteria - finds AMIs with "Netskope Private Access Publisher" in the name
# ------------------------------------------------------------------------------
data "aws_ami" "netskope_publisher" {
  count       = var.publisher_ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["*Netskope Private Access Publisher*"]
  }
}

# ------------------------------------------------------------------------------
# Netskope NPA Publisher
# ------------------------------------------------------------------------------
# Creates publisher records in the Netskope tenant.
#
# count = var.publisher_count creates multiple publishers based on user input.
# Each publisher gets a unique name using count.index:
#   - count.index 0: uses publisher_name as-is (e.g., "my-publisher")
#   - count.index 1+: appends index+1 (e.g., "my-publisher-2", "my-publisher-3")
#
# The ternary operator (?:) provides conditional naming:
#   condition ? value_if_true : value_if_false
# ------------------------------------------------------------------------------
resource "netskope_npa_publisher" "this" {
  for_each = local.publishers

  publisher_name = each.value.name
}

# ------------------------------------------------------------------------------
# Netskope NPA Publisher Token
# ------------------------------------------------------------------------------
# Generates registration tokens for each publisher.
#
# These tokens are used ONCE during instance startup to register the
# publisher with Netskope. After registration, the token is no longer needed.
#
# SECURITY NOTE:
#   - Tokens are sensitive and stored in Terraform state
#   - Ensure your state backend is encrypted (S3 with KMS)
#   - Tokens should not be logged or exposed
#
# The publisher_id references the corresponding publisher created above.
# Using count.index ensures token[0] goes with publisher[0], etc.
# ------------------------------------------------------------------------------
resource "netskope_npa_publisher_token" "this" {
  for_each = local.publishers

  publisher_id = netskope_npa_publisher.this[each.key].publisher_id
}
