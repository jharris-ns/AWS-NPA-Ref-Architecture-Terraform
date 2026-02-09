# Deployment Guide

Detailed deployment instructions for the Netskope NPA Publisher Terraform configuration, covering multiple deployment paths.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Paths Overview](#deployment-paths-overview)
- [Path A: Local State + New VPC](#path-a-local-state--new-vpc)
- [Path B: Remote State + New VPC](#path-b-remote-state--new-vpc)
- [Path C: Existing VPC](#path-c-existing-vpc)
- [Configuring Variables](#configuring-variables)
- [Reviewing the Plan](#reviewing-the-plan)
- [Applying the Configuration](#applying-the-configuration)
- [Post-Deployment Verification](#post-deployment-verification)
- [Clean Up](#clean-up)

## Prerequisites

### Tool Versions

| Tool | Minimum Version | Check Command |
|---|---|---|
| Terraform | >= 1.0 | `terraform version` |
| AWS CLI | v2 | `aws --version` |
| pre-commit (optional) | any | `pre-commit --version` |

### AWS Requirements

- **Account**: Active AWS account with billing enabled
- **Credentials**: IAM user or role with deployment permissions (see [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md))
- **Key Pair**: EC2 key pair created in the target region
- **AMI Subscription**: Netskope Private Access Publisher AMI from AWS Marketplace

### Netskope Requirements

- **Tenant**: Active Netskope tenant with NPA license
- **API Token**: REST API v2 token with these scopes:
  - Infrastructure Management (read/write)
- **Tenant URL**: Your Netskope API endpoint (e.g., `https://mytenant.goskope.com/api/v2`)

## Deployment Paths Overview

Choose the path that matches your situation:

| Path | State | VPC | Best For |
|---|---|---|---|
| **A** | Local | New | Quick start, solo developer, learning |
| **B** | Remote (S3) | New | Teams, production, CI/CD |
| **C** | Either | Existing | Integration with existing infrastructure |

## Path A: Local State + New VPC

The fastest path for getting started. State is stored locally.

### Step 1: Clone and Initialize

```bash
git clone <repository-url>
cd AWS-NPA-Ref-Architecture-Terraform/terraform

terraform init
```

### Step 2: Configure Variables

```bash
cp example.tfvars terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
# AWS
aws_region = "us-east-1"

# Publisher
publisher_name     = "my-npa-publisher"
publisher_key_name = "my-ec2-keypair"
publisher_count    = 2
```

Set sensitive values via environment variables:
```bash
export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
export TF_VAR_netskope_api_key="your-api-key"
```

### Step 3: Plan and Apply

```bash
terraform plan
terraform apply
```

### Step 4: Verify

```bash
terraform output
```

> **Limitation**: Local state cannot be shared with team members and has no locking. See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for migration to remote state.

## Path B: Remote State + New VPC

The recommended path for teams and production deployments.

### Step 1: Create State Backend Resources

Before configuring the backend, create the required AWS resources (S3 bucket, DynamoDB table, KMS key) using your preferred method (AWS Console, CLI, or CloudFormation). See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for detailed guidance on what resources are needed and their recommended configuration.

### Step 2: Configure the Backend

Edit `terraform/backend.tf` — uncomment the backend block and fill in values from your state backend resources:

```hcl
terraform {
  backend "s3" {
    bucket         = "npa-publisher-terraform-state-123456789012"
    key            = "npa-publishers/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-1:123456789012:key/abc123-..."
    dynamodb_table = "npa-publisher-terraform-lock"
  }
}
```

### Step 3: Initialize with Remote Backend

```bash
terraform init
```

If you have existing local state, use:
```bash
terraform init -migrate-state
```

### Step 4: Configure Variables and Deploy

```bash
cp example.tfvars terraform.tfvars
# Edit terraform.tfvars with your values

export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
export TF_VAR_netskope_api_key="your-api-key"

terraform plan
terraform apply
```

### Step 5: Verify

```bash
terraform output
```

State is now encrypted in S3 with DynamoDB locking. Team members can use the same backend.

## Path C: Existing VPC

Deploy publishers into an existing VPC. Works with either local or remote state.

### Requirements

Your existing VPC must have:
- **Private subnets** with NAT Gateway routing (publishers need outbound internet)
- **DNS resolution** enabled (`enableDnsSupport` and `enableDnsHostnames`)
- At least one private subnet (two recommended for multi-AZ)

### Step 1: Gather VPC Information

```bash
# Get VPC ID
aws ec2 describe-vpcs \
  --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Get private subnet IDs (subnets with NAT Gateway routing)
VPC_ID="vpc-xxxxxxxxx"
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### Step 2: Configure Variables

```hcl
# terraform.tfvars

# Disable VPC creation
create_vpc = false

# Provide existing VPC details
existing_vpc_id             = "vpc-0123456789abcdef0"
existing_private_subnet_ids = [
  "subnet-0123456789abcdef0",  # AZ1
  "subnet-0123456789abcdef1"   # AZ2
]

# VPC CIDR is still needed for security group rules
vpc_cidr = "10.0.0.0/16"

# Publisher configuration
publisher_name     = "my-npa-publisher"
publisher_key_name = "my-ec2-keypair"
```

### Step 3: Deploy

```bash
export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
export TF_VAR_netskope_api_key="your-api-key"

terraform init
terraform plan
terraform apply
```

> **Note**: When using an existing VPC, Terraform only creates the security group, IAM resources, Netskope publishers, and EC2 instances. VPC resources are not managed.

## Configuring Variables

### Three Methods

**1. terraform.tfvars file (recommended for most values):**
```hcl
# terraform.tfvars
publisher_name     = "my-npa-publisher"
publisher_key_name = "my-ec2-keypair"
publisher_count    = 2
```

**2. Environment variables (recommended for secrets):**
```bash
export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
export TF_VAR_netskope_api_key="your-api-key"
```

**3. Command-line flags:**
```bash
terraform apply \
  -var="publisher_name=my-npa-publisher" \
  -var="publisher_count=3"
```

### Security Recommendation

Never put `netskope_api_key` in `terraform.tfvars`. Use environment variables instead:

```bash
# Good — secret not written to disk
export TF_VAR_netskope_api_key="your-api-key"

# Bad — secret stored in a file
# netskope_api_key = "your-api-key"  # Don't do this
```

The `.gitignore` file excludes `terraform.tfvars` from Git, but environment variables are safer.

## Reviewing the Plan

Always review the plan before applying:

```bash
terraform plan
```

### Understanding Plan Output

```
Terraform will perform the following actions:

  # aws_instance.publisher["my-publisher"] will be created
  + resource "aws_instance" "publisher" {
      + ami                          = "ami-0123456789abcdef0"
      + instance_type                = "t3.large"
      + subnet_id                    = (known after apply)
      ...
    }

Plan: 25 to add, 0 to change, 0 to destroy.
```

Key symbols:
- `+` — Resource will be created
- `~` — Resource will be updated in-place
- `-` — Resource will be destroyed
- `-/+` — Resource will be destroyed and recreated

### Saving Plans

For CI/CD or audit purposes, save the plan to a file:

```bash
# Save plan
terraform plan -out=tfplan

# Apply the exact plan (no re-evaluation)
terraform apply tfplan
```

## Applying the Configuration

```bash
terraform apply
```

Terraform will:
1. Show the execution plan
2. Prompt for confirmation (`yes` / `no`)
3. Create resources in dependency order
4. Display outputs on completion

### Monitoring Progress

Terraform displays each resource as it's created:

```
aws_vpc.this[0]: Creating...
aws_vpc.this[0]: Creation complete after 3s [id=vpc-0123456789abcdef0]
aws_subnet.public[0]: Creating...
aws_subnet.public[1]: Creating...
...
netskope_npa_publisher.this["my-publisher"]: Creating...
netskope_npa_publisher.this["my-publisher"]: Creation complete after 2s
...
aws_instance.publisher["my-publisher"]: Creating...
aws_instance.publisher["my-publisher"]: Still creating... [10s elapsed]
aws_instance.publisher["my-publisher"]: Creation complete after 45s

Apply complete! Resources: 25 added, 0 changed, 0 destroyed.
```

### Handling Failures

If `terraform apply` fails partway through:

1. Read the error message — it identifies the specific resource and reason
2. Fix the issue (e.g., missing permission, invalid AMI, quota exceeded)
3. Run `terraform apply` again — Terraform picks up where it left off

Terraform is idempotent. Already-created resources are not recreated.

## Post-Deployment Verification

### 1. Terraform Outputs

```bash
terraform output
```

### 2. AWS Resources

```bash
# Check EC2 instances
INSTANCE_IDS=$(terraform output -json publisher_instance_ids | jq -r '.[]')
aws ec2 describe-instances \
  --instance-ids $INSTANCE_IDS \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]' \
  --output table

# Check security group
SG_ID=$(terraform output -raw security_group_id)
aws ec2 describe-security-groups --group-ids "$SG_ID"
```

### 3. Netskope UI

1. Log in to Netskope tenant
2. Navigate to **Settings → Security Cloud Platform → Publishers**
3. Verify publisher status is **Connected**

### 4. SSM Session Manager

```bash
# Connect to a publisher
INSTANCE_ID=$(terraform output -json publisher_instance_ids | jq -r '.[0]')
aws ssm start-session --target "$INSTANCE_ID"
```

### 5. Drift Detection

Run `terraform plan` periodically to check for configuration drift:

```bash
terraform plan
# "No changes" means infrastructure matches configuration
```

## Clean Up

### Destroy NPA Infrastructure

```bash
terraform destroy
```

This removes all resources managed by Terraform:
- EC2 instances
- Netskope publishers and tokens
- Security groups
- IAM roles and profiles
- VPC resources (if created by this deployment)

### Verify Cleanup

```bash
# No resources should remain in state
terraform state list

# Check AWS for any remaining resources
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=NPA-Publisher" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

## Additional Resources

- [QUICKSTART.md](QUICKSTART.md) — Fast deployment (4 steps)
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) — Remote state setup
- [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md) — Required permissions
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Common issues
- [OPERATIONS.md](OPERATIONS.md) — Day-2 operations
