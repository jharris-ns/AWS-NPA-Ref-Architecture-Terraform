# ==============================================================================
# State Infrastructure Outputs
# ==============================================================================
# These outputs provide the information needed to configure the backend
# in the main Terraform project.
#
# After running "terraform apply" in this directory, copy these values
# to backend.tf in the main project directory.
# ==============================================================================

output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
  # Use this in backend.tf as the "bucket" parameter
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
  # Useful for IAM policies if you need to grant additional access
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_lock.name
  # Use this in backend.tf as the "dynamodb_table" parameter
}

output "kms_key_arn" {
  description = "KMS key ARN for state encryption"
  value       = aws_kms_key.terraform_state.arn
  # Use this in backend.tf as the "kms_key_id" parameter
}

output "kms_key_alias" {
  description = "KMS key alias for state encryption"
  value       = aws_kms_alias.terraform_state.name
  # Alternative to using the ARN - aliases are easier to remember
}

# ------------------------------------------------------------------------------
# Ready-to-Use Backend Configuration
# ------------------------------------------------------------------------------
# This output generates the complete backend configuration block.
# Copy and paste this into backend.tf in the main project.
# ------------------------------------------------------------------------------
output "backend_config" {
  description = "Backend configuration to copy to main project"
  value       = <<-EOT
    # Copy this to backend.tf in the main project:
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        key            = "npa-publishers/terraform.tfstate"
        region         = "${var.aws_region}"
        encrypt        = true
        kms_key_id     = "${aws_kms_key.terraform_state.arn}"
        dynamodb_table = "${aws_dynamodb_table.terraform_lock.name}"
      }
    }
  EOT
  # The "key" is the path within the bucket where state is stored.
  # You can have multiple state files in one bucket by using different keys:
  #   - "npa-publishers/production/terraform.tfstate"
  #   - "npa-publishers/staging/terraform.tfstate"
}
