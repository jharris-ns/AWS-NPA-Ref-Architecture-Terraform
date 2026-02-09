# Quick Start Guide

Get your Netskope Private Access Publishers deployed on AWS with multi-AZ redundancy.

## Table of Contents

- [Prerequisites Checklist](#prerequisites-checklist)
- [Get NPA Publisher AMI ID](#get-npa-publisher-ami-id)
- [Quick Deploy](#quick-deploy)
- [Variable Reference](#variable-reference)
- [Deployment Timeline](#deployment-timeline)
- [Verify Deployment](#verify-deployment)
- [Clean Up](#clean-up)
- [Next Steps](#next-steps)

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] **Terraform** >= 1.0 installed ([install guide](https://developer.hashicorp.com/terraform/install))
- [ ] **AWS CLI** v2 installed and configured ([install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- [ ] **AWS credentials** with sufficient permissions (see [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md))
- [ ] **Netskope API v2 Token** with Infrastructure Management scope ([generate here](https://docs.netskope.com/en/rest-api-v2-overview-312207.html))
- [ ] **Netskope tenant URL** (e.g., `https://mytenant.goskope.com/api/v2`)
- [ ] **EC2 Key Pair** in your target AWS region
- [ ] **NPA Publisher AMI** subscription in AWS Marketplace (see below)
- [ ] **For existing VPC**: VPC ID and private subnet IDs with NAT Gateway routing
- [ ] **For new VPC**: Desired CIDR ranges (or use defaults)

### Verify Prerequisites

```bash
# Check Terraform version
terraform version
# Should show >= 1.0

# Check AWS CLI and credentials
aws sts get-caller-identity
# Should show your account ID and ARN

# Check EC2 key pairs in your region
aws ec2 describe-key-pairs --region us-east-1 --query 'KeyPairs[*].KeyName'
```

## Get NPA Publisher AMI ID

The NPA Publisher AMI is available from AWS Marketplace. You must subscribe before deploying.

> **Note**: If you leave `publisher_ami_id` empty, Terraform will auto-detect the latest AMI. You still need an active Marketplace subscription.

### Subscribe to the AMI

1. Go to [AWS Marketplace](https://aws.amazon.com/marketplace)
2. Search for **"Netskope Private Access Publisher"**
3. Click **Continue to Subscribe** → **Accept Terms**
4. Wait for subscription to activate (usually immediate)

### Verify AMI Access

```bash
# Find the latest NPA Publisher AMI in your region
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=*Netskope Private Access Publisher*" \
  --region us-east-1 \
  --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name,CreationDate]' \
  --output table
```

**For different regions:**
```bash
# EU (Ireland)
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=*Netskope Private Access Publisher*" \
  --region eu-west-1 \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text

# US West (Oregon)
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=*Netskope Private Access Publisher*" \
  --region us-west-2 \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text
```

If the command returns an AMI ID, you're subscribed and ready to deploy.

## Quick Deploy

### Step 1: Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd AWS-NPA-Ref-Architecture-Terraform/terraform

# Create your variables file from the example
cp example.tfvars terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Required - AWS
aws_region = "us-east-1"

# Required - Netskope (or use environment variables)
# netskope_server_url = "https://mytenant.goskope.com/api/v2"
# netskope_api_key    = "your-api-key"  # Prefer env var instead

# Required - Publisher
publisher_name     = "my-npa-publisher"
publisher_key_name = "my-ec2-keypair"

# Optional - adjust as needed
publisher_count         = 2
publisher_instance_type = "t3.large"
```

### Step 2: Set Sensitive Values via Environment Variables

```bash
# Set Netskope credentials (recommended over tfvars for secrets)
export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
export TF_VAR_netskope_api_key="your-netskope-api-key"

# Optional: Set AWS profile if not using default
export AWS_PROFILE=my-profile
```

### Step 3: Initialize and Plan

```bash
# Initialize Terraform (downloads providers)
terraform init

# Review what will be created
terraform plan
```

Review the plan output carefully. You should see resources being created for:
- VPC, subnets, NAT Gateways (if `create_vpc = true`)
- Security group
- IAM role and instance profile
- Netskope publishers and tokens
- SSM parameters (registration tokens)
- EC2 instances
- Publisher registration (null_resource)

### Step 4: Apply

```bash
# Deploy the infrastructure
terraform apply
```

Type `yes` when prompted. Terraform will create all resources.

## Variable Reference

### Required Variables

| Variable | Description | Example |
|---|---|---|
| `netskope_server_url` | Netskope API server URL | `https://mytenant.goskope.com/api/v2` |
| `netskope_api_key` | Netskope API key (sensitive) | Set via `TF_VAR_netskope_api_key` |
| `publisher_name` | Base name for publishers | `my-npa-publisher` |
| `publisher_key_name` | EC2 key pair name | `my-ec2-keypair` |

### VPC Variables

| Variable | Default | Description |
|---|---|---|
| `create_vpc` | `true` | Create new VPC or use existing |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `public_subnet_cidrs` | `["10.0.1.0/24", "10.0.3.0/24"]` | Public subnet CIDRs |
| `private_subnet_cidrs` | `["10.0.2.0/24", "10.0.4.0/24"]` | Private subnet CIDRs |
| `availability_zones` | `[]` (auto-select) | Specific AZs to use |
| `existing_vpc_id` | `""` | VPC ID when `create_vpc = false` |
| `existing_private_subnet_ids` | `[]` | Subnet IDs when `create_vpc = false` |

### Publisher Variables

| Variable | Default | Description |
|---|---|---|
| `publisher_ami_id` | `""` (auto-detect) | Specific AMI ID |
| `publisher_instance_type` | `t3.large` | EC2 instance type |
| `publisher_count` | `2` | Number of publisher instances (1-10) |

### Monitoring Variables

| Variable | Default | Description |
|---|---|---|
| `enable_cloudwatch_monitoring` | `false` | Install CloudWatch agent (~$2.40/mo per instance) |

### Tag Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS deployment region |
| `aws_profile` | `""` | AWS CLI profile name |
| `cost_center` | `IT-Operations` | Cost center for billing |
| `project` | `NPA-Publisher` | Project name tag |
| `environment` | `Production` | Environment type |
| `additional_tags` | `{}` | Extra tags for all resources |

## Deployment Timeline

Typical deployment time: **8-15 minutes**

```
t=0m    terraform apply starts
        ├─ Netskope publishers created via API
        ├─ Registration tokens generated and stored in SSM Parameter Store
        └─ VPC resources creation begins (if new VPC)

t=1-2m  VPC resources complete
        ├─ VPC, subnets, IGW created
        ├─ NAT Gateways provisioning
        └─ Security group, IAM resources created

t=3-4m  NAT Gateways available
        └─ EC2 instances launching

t=4-5m  EC2 instances running
        ├─ Optional: CloudWatch agent installs via user data
        └─ Terraform begins polling SSM for instance readiness

t=5-12m SSM-based publisher registration
        ├─ Terraform polls SSM until instances appear as "Online"
        ├─ Registration tokens fetched from SSM Parameter Store
        ├─ SSM Run Command executes npa_publisher_wizard on each instance
        └─ Terraform waits for registration to complete

t=8-15m terraform apply complete
        └─ Outputs displayed (instance IDs, IPs, publisher names)
```

## Verify Deployment

### 1. Check Terraform Outputs

```bash
# Display all outputs
terraform output

# Get specific values
terraform output publisher_instance_ids
terraform output publisher_private_ips
terraform output publisher_names
```

**Expected output:**
```
publisher_instance_ids = [
  "i-0123456789abcdef0",
  "i-0123456789abcdef1",
]
publisher_private_ips = [
  "10.0.2.50",
  "10.0.4.75",
]
publisher_names = [
  "my-npa-publisher",
  "my-npa-publisher-2",
]
```

### 2. Verify in Netskope UI

1. Log in to your Netskope tenant
2. Go to **Settings → Security Cloud Platform → Publishers**
3. Look for publishers named `my-npa-publisher` and `my-npa-publisher-2`
4. Status should be: **Connected** (may take 1-2 minutes after deployment)

### 3. Check EC2 Instances

```bash
# Get instance status
INSTANCE_IDS=$(terraform output -json publisher_instance_ids | jq -r '.[]')

for id in $INSTANCE_IDS; do
  echo "Instance: $id"
  aws ec2 describe-instances \
    --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].[State.Name,PrivateIpAddress]' \
    --output text
done
```

### 4. Test SSM Session Manager Access

```bash
# Connect to a publisher instance (no SSH key needed)
INSTANCE_ID=$(terraform output -json publisher_instance_ids | jq -r '.[0]')
aws ssm start-session --target "$INSTANCE_ID"

# Once connected, check publisher status:
systemctl status npa_publisher_wizard || systemctl status npa_publisher
```

## Clean Up

```bash
# Destroy all resources created by Terraform
terraform destroy
```

Type `yes` when prompted. This will:
- Terminate EC2 instances
- Delete Netskope publishers (via the Netskope provider)
- Delete security group, IAM resources
- Delete VPC resources (if created by this deployment)

**Verify cleanup:**
```bash
# Confirm no resources remain
terraform state list
# Should return empty
```

## Next Steps

1. **Set up remote state** — For team use, create an S3 backend for state storage and locking. See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md).

2. **Review security** — Understand the security architecture and IAM permissions. See [ARCHITECTURE.md](ARCHITECTURE.md) and [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md).

3. **Configure monitoring** — Enable CloudWatch monitoring by setting `enable_cloudwatch_monitoring = true`. See [OPERATIONS.md](OPERATIONS.md).

4. **Set up pre-commit hooks** — Install quality gates for your team:
   ```bash
   pip install pre-commit
   pre-commit install
   ```

5. **Plan for operations** — Review day-2 procedures for scaling, upgrades, and troubleshooting. See [OPERATIONS.md](OPERATIONS.md) and [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Additional Resources

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — Detailed deployment with multiple paths
- [ARCHITECTURE.md](ARCHITECTURE.md) — Architecture deep-dive
- [DEVOPS-NOTES.md](DEVOPS-NOTES.md) — Technical patterns and provider details
- [Netskope REST API v2](https://docs.netskope.com/en/rest-api-v2-overview-312207.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Netskope Terraform Provider](https://registry.terraform.io/providers/netskope/netskope/latest/docs)
