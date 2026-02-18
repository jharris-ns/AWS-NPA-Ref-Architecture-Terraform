# ==============================================================================
# Data Sources
# ==============================================================================
# Data sources fetch information from providers WITHOUT creating resources.
# They're read-only queries that return existing data.
#
# AWS I&A Standard: Group data sources in data.tf when they exceed a few
# lines or when main.tf becomes too large (>150 lines for a single service).
# ==============================================================================

# ------------------------------------------------------------------------------
# Available Availability Zones
# ------------------------------------------------------------------------------
# Queries AWS for all available AZs in the current region.
# This allows the config to automatically adapt to any region without
# hardcoding AZ names like "us-east-1a".
#
# state = "available": Only return AZs that are currently operational
# ------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------------------------
# Current AWS Account and Region
# ------------------------------------------------------------------------------
# Used for constructing IAM policy ARNs scoped to the current account/region.
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
