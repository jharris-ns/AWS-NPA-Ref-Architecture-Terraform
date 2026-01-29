# ==============================================================================
# Terraform and Provider Version Constraints
# ==============================================================================
# This file declares the required Terraform version and provider dependencies.
# Separating this from main.tf follows AWS I&A standards and makes version
# management clearer.
#
# Version constraint operators:
#   = 1.0.0   - Exact version only
#   >= 1.0.0  - Minimum version (allows any newer)
#   ~> 1.0    - Pessimistic constraint (allows 1.x but not 2.0)
#   >= 1.0, < 2.0 - Range constraint
# ==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS provider for infrastructure resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    # Netskope provider for NPA publisher management
    # Note: Local dev overrides in ~/.terraformrc take precedence over version constraints
    netskope = {
      source  = "netskopeoss/netskope"
      version = ">= 0.3.3"
    }
  }
}
