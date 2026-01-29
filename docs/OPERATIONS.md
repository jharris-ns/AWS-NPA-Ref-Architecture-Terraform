# NPA Publisher Operational Procedures

Day-2 operational procedures for managing NPA Publisher deployments with Terraform.

## Table of Contents

- [Publisher Upgrades](#publisher-upgrades)
- [Scaling Publishers](#scaling-publishers)
- [Rotate Netskope API Token](#rotate-netskope-api-token)
- [Replace a Failed Publisher](#replace-a-failed-publisher)
- [Manual Publisher Registration](#manual-publisher-registration)
- [Import Existing Resources](#import-existing-resources)
- [Backup and Restore](#backup-and-restore)
- [Monitoring and Alerts](#monitoring-and-alerts)

## Publisher Upgrades

### Auto-Updates (Recommended)

Netskope publishers support automatic upgrades managed through the Netskope console. This is the recommended method — no Terraform changes required.

**Configure auto-updates in Netskope UI:**

1. Log in to your Netskope tenant
2. Go to **Settings → Security Cloud Platform → Publishers**
3. Select your publisher group
4. Enable **Auto-Update** and configure the maintenance window
5. Choose update schedule (weekly, monthly)

**Benefits:**
- No manual intervention required
- Minimal downtime during updates
- Automatic rollback on failure
- No infrastructure replacement needed
- Controlled maintenance windows

**Documentation:** [Configure Publisher Auto-Updates](https://docs.netskope.com/en/configure-publisher-auto-updates)

### AMI Replacement

If you need to replace the underlying EC2 instance with a newer AMI:

**Step 1: Find the latest AMI:**
```bash
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=*Netskope Private Access Publisher*" \
  --region us-east-1 \
  --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name,CreationDate]' \
  --output table
```

**Step 2: Update the AMI variable:**
```hcl
# terraform.tfvars
publisher_ami_id = "ami-NEW_AMI_ID"
```

**Step 3: Replace instances:**
```bash
# Replace one instance at a time for zero-downtime
terraform apply -replace='aws_instance.publisher["my-publisher"]'
# Wait for the new instance to register with Netskope
terraform apply -replace='aws_instance.publisher["my-publisher-2"]'
```

> **Note**: Because `ignore_changes = [ami, user_data]` is set, changing `publisher_ami_id` alone will not trigger replacement. You must explicitly use `-replace`.

**Step 4: Verify in Netskope UI:**
- Check **Settings → Security Cloud Platform → Publishers**
- Verify both publishers show **Connected** status

## Scaling Publishers

### Horizontal Scaling (Add/Remove Instances)

**Scale up — add publishers:**
```hcl
# terraform.tfvars
publisher_count = 4  # Was 2
```

```bash
terraform plan
# Should show 2 new resources to add

terraform apply
```

New publishers are automatically:
- Distributed across availability zones
- Registered with Netskope
- Named sequentially (e.g., `my-publisher-3`, `my-publisher-4`)

**Scale down — remove publishers:**
```hcl
# terraform.tfvars
publisher_count = 1  # Was 2
```

```bash
terraform plan
# Should show resources to destroy for "my-publisher-2"

terraform apply
```

Terraform removes publishers from Netskope and terminates the EC2 instances. The `for_each` pattern ensures only the specified publishers are removed — existing ones are untouched.

### Vertical Scaling (Change Instance Type)

**Step 1: Update instance type:**
```hcl
# terraform.tfvars
publisher_instance_type = "t3.xlarge"  # Was t3.large
```

**Step 2: Replace instances:**
```bash
# Instance type changes require replacement
terraform apply -replace='aws_instance.publisher["my-publisher"]'
terraform apply -replace='aws_instance.publisher["my-publisher-2"]'
```

**Supported instance types:**

| Type | vCPU | Memory | Use Case |
|---|---|---|---|
| `t3.medium` | 2 | 4 GB | Light workloads |
| `t3.large` | 2 | 8 GB | Standard workloads (default) |
| `t3.xlarge` | 4 | 16 GB | Heavy workloads |
| `t3.2xlarge` | 8 | 32 GB | Very heavy workloads |
| `m5.large` | 2 | 8 GB | Memory-intensive |
| `m5.xlarge` | 4 | 16 GB | Memory-intensive, heavy |
| `m5.2xlarge` | 8 | 32 GB | Memory-intensive, very heavy |

## Rotate Netskope API Token

The Netskope API token authenticates Terraform with the Netskope API. Rotation is straightforward because existing publishers are not affected by token changes.

### Step 1: Generate New Token

1. Log in to Netskope tenant
2. Go to **Settings → Tools → REST API v2**
3. Click **New Token**
4. Name: `NPA-Publisher-Rotated-<Date>`
5. Enable scope: **Infrastructure Management**
6. Copy the new token

### Step 2: Update Environment Variable

```bash
export TF_VAR_netskope_api_key="new-api-key-here"
```

Or update your secrets management system (Vault, AWS SSM, etc.).

### Step 3: Verify

```bash
# Terraform should be able to read existing publishers
terraform plan
# Should show "No changes" if everything is correct
```

### Step 4: Revoke Old Token (Optional)

1. Go to **Settings → Tools → REST API v2** in Netskope UI
2. Find the old token
3. Click **Revoke**

> **Note**: Existing publishers continue operating normally regardless of API token changes. The API token is only used by Terraform, not by the running publishers. Publisher-to-Netskope connectivity is established during registration and does not depend on the API token.

## Replace a Failed Publisher

### Single Instance Replacement

```bash
# Replace the specific failed instance
terraform apply -replace='aws_instance.publisher["my-publisher"]'
```

This will:
1. Terminate the old EC2 instance
2. Generate a new registration token (if the Netskope publisher resource is also replaced)
3. Launch a new EC2 instance with the new token
4. The new instance auto-registers with Netskope on boot

### Full Publisher Replacement (Including Netskope Record)

If you need to completely re-register the publisher:

```bash
# Replace the Netskope publisher (creates new record + token)
terraform apply \
  -replace='netskope_npa_publisher.this["my-publisher"]' \
  -replace='netskope_npa_publisher_token.this["my-publisher"]' \
  -replace='aws_instance.publisher["my-publisher"]'
```

### Check Instance Health

```bash
# Get instance IDs
INSTANCE_IDS=$(terraform output -json publisher_instance_ids | jq -r '.[]')

# Check EC2 status
for id in $INSTANCE_IDS; do
  echo "=== $id ==="
  aws ec2 describe-instance-status \
    --instance-ids "$id" \
    --query 'InstanceStatuses[0].[InstanceState.Name,SystemStatus.Status,InstanceStatus.Status]' \
    --output text
done

# Check SSM registration
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$(echo $INSTANCE_IDS | tr ' ' ',')" \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,LastPingDateTime]' \
  --output table
```

## Manual Publisher Registration

If automatic registration via user data fails, you can register manually via SSM Session Manager.

### Step 1: Connect to the Instance

```bash
INSTANCE_ID=$(terraform output -json publisher_instance_ids | jq -r '.[0]')
aws ssm start-session --target "$INSTANCE_ID"
```

### Step 2: Get the Registration Token

The token is available in the Terraform state:

```bash
# From your workstation (not the instance)
terraform state show 'netskope_npa_publisher_token.this["my-publisher"]'
# Look for the "token" attribute
```

Or generate a new token via the Netskope API:

```bash
# Get API token
NETSKOPE_API_KEY="your-api-key"
NETSKOPE_URL="https://mytenant.goskope.com/api/v2"

# Get publisher ID
PUBLISHER_ID=$(terraform state show 'netskope_npa_publisher.this["my-publisher"]' | grep publisher_id | awk '{print $3}' | tr -d '"')

# Generate new registration token (check provider docs for exact endpoint)
curl -H "Netskope-Api-Token: $NETSKOPE_API_KEY" \
  "$NETSKOPE_URL/infrastructure/publishers/$PUBLISHER_ID/registration_token"
```

### Step 3: Run Registration Wizard

On the instance (via SSM session):

```bash
sudo /home/ubuntu/npa_publisher_wizard -token "YOUR_REGISTRATION_TOKEN"
```

### Step 4: Verify

```bash
# On the instance
systemctl status npa_publisher_wizard || systemctl status npa_publisher

# From the Netskope UI
# Settings → Security Cloud Platform → Publishers → verify "Connected"
```

## Import Existing Resources

If you have existing AWS resources that you want Terraform to manage:

### Import Commands

```bash
# Import EC2 instance
terraform import 'aws_instance.publisher["my-publisher"]' i-0123456789abcdef0

# Import VPC
terraform import 'aws_vpc.this[0]' vpc-0123456789abcdef0

# Import security group
terraform import 'aws_security_group.publisher' sg-0123456789abcdef0

# Import IAM role
terraform import 'aws_iam_role.publisher' publisher-role-name

# Import IAM instance profile
terraform import 'aws_iam_instance_profile.publisher' publisher-profile-name
```

### Post-Import Steps

1. Run `terraform plan` to see differences between configuration and imported state
2. Update `.tf` files to match actual resource configuration
3. Run `terraform plan` again to confirm "No changes"

> **Note**: Import only adds resources to state — it does not modify the actual resources or generate configuration.

## Backup and Restore

### Configuration Backup

Your Terraform configuration files (`.tf`) should be in Git:

```bash
git add terraform/*.tf terraform/example.tfvars
git commit -m "Configuration backup"
git push
```

> **Never commit**: `terraform.tfvars` (may contain non-sensitive configs but is excluded by `.gitignore` for safety), `*.tfstate` files, or sensitive environment variables.

### State Backup

**With remote state (S3):**

S3 versioning is enabled by default. Every `terraform apply` creates a new version. To manually backup:

```bash
# Pull state to local file
terraform state pull > state-backup-$(date +%Y%m%d).json
```

**Recover previous state:**
```bash
# List versions
aws s3api list-object-versions \
  --bucket npa-publisher-terraform-state-ACCOUNT_ID \
  --prefix npa-publishers/terraform.tfstate \
  --query 'Versions[0:5].[VersionId,LastModified]' \
  --output table

# Download a previous version
aws s3api get-object \
  --bucket npa-publisher-terraform-state-ACCOUNT_ID \
  --key npa-publishers/terraform.tfstate \
  --version-id "VERSION_ID" \
  recovered-state.json

# Push recovered state
terraform state push recovered-state.json
```

See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for complete disaster recovery procedures.

### Infrastructure Backup

Export current resource configuration for reference:

```bash
# Export current outputs
terraform output -json > outputs-backup-$(date +%Y%m%d).json

# Export instance details
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=NPA-Publisher" \
  --output json > instances-backup-$(date +%Y%m%d).json
```

## Monitoring and Alerts

### CloudWatch Monitoring

**Enable CloudWatch agent** (collects memory and disk metrics):
```hcl
# terraform.tfvars
enable_cloudwatch_monitoring = true
```

```bash
terraform apply
```

This installs the CloudWatch agent on all publisher instances and configures it to collect:
- CPU utilization
- Memory utilization
- Disk utilization
- Swap utilization
- Collection interval: 60 seconds
- Namespace: `NPA/Publisher`

### CloudWatch Alarms

Create alarms for publisher health:

```bash
INSTANCE_ID=$(terraform output -json publisher_instance_ids | jq -r '.[0]')

# CPU utilization alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "NPA-Publisher-HighCPU" \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID"

# Instance status check alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "NPA-Publisher-StatusCheck" \
  --alarm-description "Alert when status check fails" \
  --metric-name StatusCheckFailed \
  --namespace AWS/EC2 \
  --statistic Maximum \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID"
```

### Netskope UI Monitoring

Check publisher health in the Netskope console:
1. **Settings → Security Cloud Platform → Publishers**
2. Verify status: **Connected** (green)
3. Check last seen timestamp

### Drift Detection with Terraform

Run `terraform plan` periodically to detect configuration drift:

```bash
terraform plan
```

- **"No changes"** — Infrastructure matches configuration
- **Changes detected** — Something was modified outside of Terraform

For CI/CD pipelines:
```bash
terraform plan -detailed-exitcode
# Exit code 0: No changes
# Exit code 1: Error
# Exit code 2: Changes detected
```

### Key Metrics to Monitor

| Metric | Source | Threshold | Action |
|---|---|---|---|
| Instance Status | EC2 | StatusCheckFailed >= 1 | Replace instance |
| CPU Utilization | EC2 | > 80% sustained | Scale up instance type |
| Memory Utilization | CloudWatch Agent | > 85% | Scale up instance type |
| Disk Utilization | CloudWatch Agent | > 80% | Investigate |
| Publisher Status | Netskope UI | Not Connected | Troubleshoot |
| `terraform plan` | Terraform | Changes detected | Investigate drift |

## Additional Resources

- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Issue diagnosis and resolution
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) — State operations and recovery
- [ARCHITECTURE.md](ARCHITECTURE.md) — Architecture reference
- [Netskope Publisher Admin Guide](https://docs.netskope.com/en/netskope-help/admin/private-access/publishers)
