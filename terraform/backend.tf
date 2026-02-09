# ==============================================================================
# Terraform Backend Configuration
# ==============================================================================
# The backend determines where Terraform stores its state file.
#
# By default, Terraform uses a "local" backend that stores state in the
# current directory as terraform.tfstate. This works for learning but
# has problems for real projects:
#   - State may contain secrets (stored in plain text locally)
#   - Team members can't share state
#   - No locking = concurrent runs can corrupt state
#   - No versioning = hard to recover from mistakes
#
# The S3 backend solves these problems:
#   - State is encrypted at rest with KMS
#   - State is encrypted in transit with HTTPS
#   - DynamoDB provides locking for safe concurrent access
#   - S3 versioning allows recovery of previous state
#   - IAM controls who can access state
#
# SETUP INSTRUCTIONS:
#   1. Create the required AWS resources (S3 bucket, DynamoDB table, KMS key).
#      See docs/STATE_MANAGEMENT.md for detailed guidance.
#
#   2. Uncomment the backend block below and fill in the values
#
#   3. Initialize with the new backend:
#      terraform init -migrate-state
#      (This moves local state to S3)
#
# IMPORTANT: After configuring the backend, you cannot change it without
# running "terraform init -migrate-state" again.
# ==============================================================================

# Uncomment and configure after creating your state backend resources
#
# terraform {
#   backend "s3" {
#     # S3 bucket name
#     bucket = "npa-publisher-terraform-state-ACCOUNT_ID"
#
#     # Path within the bucket for this state file
#     # Use different keys for different environments:
#     #   - "npa-publishers/production/terraform.tfstate"
#     #   - "npa-publishers/staging/terraform.tfstate"
#     key = "npa-publishers/terraform.tfstate"
#
#     # AWS region where the bucket is located
#     region = "us-east-1"
#
#     # Enable server-side encryption
#     encrypt = true
#
#     # KMS key ARN for encryption
#     kms_key_id = "arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID"
#
#     # DynamoDB table for state locking
#     dynamodb_table = "npa-publisher-terraform-lock"
#   }
# }
