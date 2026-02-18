# ==============================================================================
# TFLint Configuration
# ==============================================================================
# TFLint is a Terraform linter that detects errors and enforces best practices
# not covered by `terraform validate`.
#
# Installation:
#   brew install tflint                    # macOS
#   choco install tflint                   # Windows
#   curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
#
# Usage:
#   tflint --init     # Initialize plugins (run first)
#   tflint            # Run linter
#   tflint --fix      # Auto-fix some issues
#
# CI/CD Integration:
#   Run tflint before terraform plan to catch issues early.
# ==============================================================================

# ------------------------------------------------------------------------------
# TFLint Core Configuration
# ------------------------------------------------------------------------------
config {
  # Enable module inspection (checks modules referenced by the root module)
  call_module_type = "local"

  # Enforce all rules by default
  force = false

  # Disable specific rules if needed
  # disabled_by_default = false
}

# ------------------------------------------------------------------------------
# AWS Plugin
# ------------------------------------------------------------------------------
# The AWS plugin provides AWS-specific rules that validate:
#   - Instance types exist
#   - AMI IDs are valid format
#   - IAM policy syntax
#   - Security group rules
#   - And many more AWS-specific checks
#
# Full rule list: https://github.com/terraform-linters/tflint-ruleset-aws
# ------------------------------------------------------------------------------
plugin "aws" {
  enabled = true
  version = "0.31.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# ------------------------------------------------------------------------------
# Terraform Plugin (Built-in Rules)
# ------------------------------------------------------------------------------
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# ==============================================================================
# Rule Configurations
# ==============================================================================
# Rules can be configured to change severity or disable them entirely.
# Severity levels: error, warning, notice
# ==============================================================================

# ------------------------------------------------------------------------------
# Terraform Language Rules
# ------------------------------------------------------------------------------

# Ensure all variables have descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Ensure all outputs have descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Ensure consistent naming convention (snake_case)
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Warn about deprecated syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Ensure terraform blocks have required_version
rule "terraform_required_version" {
  enabled = true
}

# Ensure all providers have version constraints
rule "terraform_required_providers" {
  enabled = true
}

# Warn about unused variables
rule "terraform_unused_declarations" {
  enabled = true
}

# Ensure standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# ------------------------------------------------------------------------------
# AWS-Specific Rules
# ------------------------------------------------------------------------------

# Validate EC2 instance types exist
rule "aws_instance_invalid_type" {
  enabled = true
}

# Validate AMI ID format
rule "aws_instance_invalid_ami" {
  enabled = true
}

# Warn about previous generation instance types
rule "aws_instance_previous_type" {
  enabled = true
}

# Validate IAM policy syntax
rule "aws_iam_policy_document_gov_friendly_arns" {
  enabled = true
}

# Validate security group rule protocols
rule "aws_security_group_invalid_protocol" {
  enabled = true
}
