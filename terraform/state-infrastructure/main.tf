# ==============================================================================
# Terraform State Infrastructure
# ==============================================================================
# This creates the infrastructure needed to store Terraform state securely.
#
# WHY REMOTE STATE?
# By default, Terraform stores state locally in terraform.tfstate. This is
# problematic for teams because:
#   - State can get out of sync if multiple people run Terraform
#   - State files may contain sensitive data (passwords, tokens)
#   - No locking means concurrent runs can corrupt state
#
# This configuration creates:
#   - S3 bucket: Stores the state file with versioning and encryption
#   - KMS key: Encrypts the state file at rest
#   - DynamoDB table: Provides locking to prevent concurrent modifications
#
# USAGE:
#   1. Run this configuration FIRST: terraform init && terraform apply
#   2. Note the outputs (bucket name, KMS key ARN, DynamoDB table name)
#   3. Configure backend.tf in the main project with these values
#   4. Run terraform init in the main project to migrate state to S3
# ==============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# KMS Key for State Encryption
# ------------------------------------------------------------------------------
# AWS Key Management Service (KMS) provides encryption keys.
# This key encrypts the Terraform state file in S3.
#
# Key features:
#   - deletion_window_in_days: Waiting period before key is deleted (protection)
#   - enable_key_rotation: Automatically rotates key material annually
#   - policy: Controls who can use the key (IAM principals)
#
# The policy has two statements:
#   1. Root account access: Allows the AWS account to manage the key
#   2. Terraform access: Allows specified roles/users to encrypt/decrypt
# ------------------------------------------------------------------------------
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 30   # 30-day waiting period before deletion
  enable_key_rotation     = true # Security best practice

  # Key policy in JSON format
  # jsonencode() converts HCL to JSON
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow the AWS account root to manage the key
        # This is required - without it, the key becomes unmanageable
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*" # All KMS actions
        Resource = "*"     # This key (in key policies, * means "this key")
      },
      {
        # Allow specified IAM roles/users to use the key for encryption
        Sid    = "Allow Terraform State Access"
        Effect = "Allow"
        Principal = {
          AWS = var.terraform_admin_role_arns # List of allowed IAM ARNs
        }
        Action = [
          "kms:Encrypt",         # Encrypt data
          "kms:Decrypt",         # Decrypt data
          "kms:GenerateDataKey", # Generate data keys for envelope encryption
          "kms:DescribeKey"      # Get key metadata
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = "${var.project_name}-terraform-state-key"
    Project = var.project_name
  }
}

# ------------------------------------------------------------------------------
# KMS Key Alias
# ------------------------------------------------------------------------------
# Aliases provide friendly names for KMS keys.
# Instead of using the key ID (a UUID), you can use alias/my-key-name.
# This makes it easier to identify keys in the console and in code.
# ------------------------------------------------------------------------------
resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ------------------------------------------------------------------------------
# S3 Bucket for State Storage
# ------------------------------------------------------------------------------
# S3 (Simple Storage Service) stores the Terraform state file.
#
# The bucket name includes the AWS account ID to ensure uniqueness:
# S3 bucket names must be globally unique across ALL AWS accounts.
#
# Note: We use separate resources for bucket configuration (versioning,
# encryption, etc.) rather than inline blocks. This is the modern approach
# and allows for more granular control.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  # Bucket name format: {project}-terraform-state-{account_id}
  bucket = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project_name}-terraform-state"
    Project = var.project_name
  }
}

# ------------------------------------------------------------------------------
# Block All Public Access
# ------------------------------------------------------------------------------
# CRITICAL SECURITY SETTING: Prevents accidental public exposure.
#
# S3 buckets can accidentally become public through:
#   - Bucket policies
#   - ACLs (Access Control Lists)
#   - Object-level permissions
#
# This resource blocks ALL public access methods:
#   - block_public_acls: Reject PUT requests with public ACLs
#   - block_public_policy: Reject bucket policies that grant public access
#   - ignore_public_acls: Ignore any public ACLs on objects
#   - restrict_public_buckets: Restrict access to AWS principals only
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Enable Versioning
# ------------------------------------------------------------------------------
# Versioning keeps multiple versions of the state file.
#
# Benefits:
#   - Recovery: Roll back to previous state if something goes wrong
#   - Audit trail: See how state changed over time
#   - Protection: Accidental deletions can be recovered
#
# With versioning, deleting an object just adds a "delete marker" -
# the actual data is preserved and can be restored.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# Server-Side Encryption with KMS
# ------------------------------------------------------------------------------
# Encrypts all objects stored in the bucket using our KMS key.
#
# SSE-KMS (Server-Side Encryption with KMS) provides:
#   - Encryption at rest with customer-managed keys
#   - Audit trail in CloudTrail for key usage
#   - Fine-grained access control via key policies
#
# bucket_key_enabled reduces KMS API calls (and costs) by using
# a bucket-level key derived from the KMS key.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state.arn
      sse_algorithm     = "aws:kms" # Use KMS encryption (not S3-managed keys)
    }
    bucket_key_enabled = true # Reduce KMS costs
  }
}

# ------------------------------------------------------------------------------
# Bucket Policy: Require SSL and Restrict Access
# ------------------------------------------------------------------------------
# Bucket policies control access to the bucket and its objects.
#
# This policy has two statements:
#   1. RequireSSL: Deny any request not using HTTPS
#   2. AllowTerraformAccess: Allow specific IAM roles to access state
#
# The Condition block in RequireSSL checks aws:SecureTransport:
#   - true = HTTPS request
#   - false = HTTP request (unencrypted)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Deny all non-HTTPS requests
        # This ensures state is always transmitted encrypted
        Sid       = "RequireSSL"
        Effect    = "Deny"
        Principal = "*"    # Applies to everyone
        Action    = "s3:*" # All S3 actions
        Resource = [
          aws_s3_bucket.terraform_state.arn,       # Bucket itself
          "${aws_s3_bucket.terraform_state.arn}/*" # All objects in bucket
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false" # When NOT using HTTPS
          }
        }
      },
      {
        # Allow Terraform administrators to access state
        Sid    = "AllowTerraformAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.terraform_admin_role_arns
        }
        Action = [
          "s3:GetObject",    # Read state
          "s3:PutObject",    # Write state
          "s3:DeleteObject", # Delete state (for terraform destroy)
          "s3:ListBucket"    # List bucket contents
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# DynamoDB Table for State Locking
# ------------------------------------------------------------------------------
# DynamoDB provides state locking to prevent concurrent modifications.
#
# When Terraform runs:
#   1. It acquires a lock by writing to this table
#   2. If another process has the lock, Terraform waits or fails
#   3. After completion, Terraform releases the lock
#
# This prevents scenarios where two people run "terraform apply" simultaneously,
# which could corrupt state or create conflicting resources.
#
# Table configuration:
#   - billing_mode: PAY_PER_REQUEST means you only pay for actual usage
#     (no need to provision capacity for occasional Terraform runs)
#   - hash_key: LockID is the partition key (required by Terraform)
# ------------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "${var.project_name}-terraform-lock"
  billing_mode = "PAY_PER_REQUEST" # On-demand pricing
  hash_key     = "LockID"          # Primary key (required name by Terraform)

  # Define the LockID attribute
  # S = String type
  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "${var.project_name}-terraform-lock"
    Project = var.project_name
  }
}

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------
# Data sources fetch information from AWS without creating resources.
#
# aws_caller_identity returns information about the IAM identity making
# the API call, including the AWS account ID. We use this to:
#   - Create globally unique S3 bucket names
#   - Reference the account in IAM policies
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
