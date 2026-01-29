# Terraform State Management

Comprehensive guide to managing Terraform state for the NPA Publisher deployment. State management is critical for security, collaboration, and disaster recovery.

## Table of Contents

- [What is Terraform State?](#what-is-terraform-state)
- [Local State](#local-state)
- [Remote State with S3](#remote-state-with-s3)
- [The state-infrastructure Module](#the-state-infrastructure-module)
- [Configuring the S3 Backend](#configuring-the-s3-backend)
- [Migration: Local to Remote](#migration-local-to-remote)
- [State Security](#state-security)
- [State Operations](#state-operations)
- [Team Workflow](#team-workflow)
- [Disaster Recovery](#disaster-recovery)
- [Cost](#cost)

## What is Terraform State?

Terraform state is a JSON file that maps your configuration to real-world infrastructure. Every time you run `terraform apply`, Terraform records what it created so it can manage those resources on future runs.

### What State Tracks

- **Resource IDs**: EC2 instance IDs, security group IDs, VPC IDs
- **Attribute values**: Private IPs, ARNs, names, configuration details
- **Dependencies**: Which resources depend on which others
- **Metadata**: Provider configuration, Terraform version, serial number

### Why State Matters

Without state, Terraform cannot:
- Know which resources it manages (vs. resources created manually)
- Detect drift between desired and actual configuration
- Determine the correct order to create, update, or destroy resources
- Map configuration blocks to real infrastructure

### Sensitive Data in State

**This is the most important thing to understand about state.**

Terraform state stores resource attributes in plain text. For this project, state contains:

- **Netskope API key** (from the provider configuration)
- **Netskope publisher registration tokens** (from `netskope_npa_publisher_token`)
- **EC2 instance metadata** (private IPs, instance IDs)
- **IAM role ARNs and policy documents**
- **Security group rules** (including Netskope NewEdge IP ranges)

> **Warning**: Anyone who can read your state file can see your Netskope API key and registration tokens. Treat state files with the same care as credentials.

## Local State

### Default Behavior

By default, Terraform stores state in a file called `terraform.tfstate` in the working directory. A backup of the previous state is kept in `terraform.tfstate.backup`.

```
project/
├── main.tf
├── variables.tf
├── terraform.tfstate        ← Current state (contains secrets)
└── terraform.tfstate.backup ← Previous state
```

### When Local State is Appropriate

- **Learning and experimentation**: Testing Terraform concepts
- **Solo developer projects**: No team collaboration needed
- **Ephemeral environments**: Destroyed after each use (CI/CD test runs)
- **Quick prototyping**: Before committing to remote state infrastructure

### Security Precautions for Local State

If using local state, take these precautions:

**1. Never commit state to Git:**

The `.gitignore` file in this project already excludes state files:
```gitignore
*.tfstate
*.tfstate.*
```

Verify this is working:
```bash
git status | grep tfstate
# Should return nothing
```

**2. Restrict file permissions:**
```bash
chmod 600 terraform.tfstate
chmod 600 terraform.tfstate.backup
```

**3. Encrypt at rest:**

On macOS, enable FileVault. On Linux, use LUKS or similar disk encryption.

### Limitations of Local State

| Limitation | Impact |
|---|---|
| No encryption at rest | Secrets visible in plain text on disk |
| No locking | Concurrent runs can corrupt state |
| No versioning | Cannot recover from mistakes |
| No sharing | Team members cannot collaborate |
| No audit trail | No record of who changed what |

## Remote State with S3

### Why S3 + DynamoDB + KMS?

The S3 backend is the recommended approach for production deployments. It combines three AWS services:

| Service | Purpose | Benefit |
|---|---|---|
| **S3** | State file storage | Durable, versioned, accessible from anywhere |
| **DynamoDB** | State locking | Prevents concurrent modifications |
| **KMS** | Encryption | Encrypts state at rest with customer-managed keys |

### Benefits Over Local State

- **Encryption at rest**: KMS encrypts state before writing to S3
- **Encryption in transit**: HTTPS enforced via bucket policy
- **Locking**: DynamoDB prevents two people from running `terraform apply` simultaneously
- **Versioning**: S3 versioning allows recovery of any previous state
- **Access control**: IAM policies control who can read/write state
- **Audit trail**: CloudTrail logs all S3 and KMS access
- **Durability**: S3 provides 99.999999999% (11 nines) durability
- **Availability**: S3 provides 99.99% availability

### How It Works

```
terraform apply
    │
    ├─ 1. Acquire lock (DynamoDB)
    │     └─ Write lock record with operator identity
    │
    ├─ 2. Read state (S3)
    │     └─ Download and decrypt (KMS) current state
    │
    ├─ 3. Plan and apply changes
    │     └─ Create/update/destroy AWS resources
    │
    ├─ 4. Write state (S3)
    │     └─ Encrypt (KMS) and upload new state
    │     └─ Previous version preserved (S3 versioning)
    │
    └─ 5. Release lock (DynamoDB)
          └─ Delete lock record
```

## The state-infrastructure Module

This project includes a `terraform/state-infrastructure/` directory that creates all the AWS resources needed for remote state.

### What It Creates

| Resource | Name Pattern | Purpose |
|---|---|---|
| **KMS Key** | `alias/npa-publisher-terraform-state` | Encrypts state file |
| **S3 Bucket** | `npa-publisher-terraform-state-{ACCOUNT_ID}` | Stores state file |
| **DynamoDB Table** | `npa-publisher-terraform-lock` | State locking |

### Security Features

The module applies these security controls automatically:

- **KMS key rotation** enabled (annual automatic rotation)
- **S3 public access** blocked (all four block settings enabled)
- **S3 versioning** enabled (recover previous state versions)
- **S3 bucket policy** requires HTTPS and restricts access to specified IAM ARNs
- **KMS key policy** restricts encrypt/decrypt to specified IAM ARNs

### Step-by-Step Deployment

**1. Navigate to the state infrastructure directory:**
```bash
cd terraform/state-infrastructure
```

**2. Initialize Terraform:**
```bash
terraform init
```

**3. Create a variables file:**
```bash
cat > terraform.tfvars <<'EOF'
aws_region   = "us-east-1"
project_name = "npa-publisher"

# IMPORTANT: Replace with YOUR IAM role/user ARNs
terraform_admin_role_arns = [
  "arn:aws:iam::123456789012:role/TerraformAdmin",
  "arn:aws:iam::123456789012:user/your-username"
]
EOF
```

> **Tip**: Find your current ARN with:
> ```bash
> aws sts get-caller-identity --query Arn --output text
> ```

**4. Review the plan:**
```bash
terraform plan
```

Expected output shows creation of:
- 1 KMS key + 1 alias
- 1 S3 bucket + public access block + versioning + encryption config + bucket policy
- 1 DynamoDB table

**5. Apply:**
```bash
terraform apply
```

Type `yes` when prompted.

**6. Save the outputs:**
```bash
terraform output
```

Example output:
```
state_bucket_name  = "npa-publisher-terraform-state-123456789012"
dynamodb_table_name = "npa-publisher-terraform-lock"
kms_key_arn        = "arn:aws:kms:us-east-1:123456789012:key/abc123-..."
kms_key_alias      = "alias/npa-publisher-terraform-state"

backend_config = <<EOT
  # Copy this to backend.tf in the main project:
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
EOT
```

### Variables Reference

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `us-east-1` | AWS region for state infrastructure |
| `project_name` | string | `npa-publisher` | Prefix for all resource names |
| `terraform_admin_role_arns` | list(string) | *required* | IAM ARNs allowed to access state |

### Outputs Reference

| Output | Description |
|---|---|
| `state_bucket_name` | S3 bucket name — use as `bucket` in backend config |
| `state_bucket_arn` | S3 bucket ARN — use in IAM policies |
| `dynamodb_table_name` | DynamoDB table name — use as `dynamodb_table` in backend config |
| `kms_key_arn` | KMS key ARN — use as `kms_key_id` in backend config |
| `kms_key_alias` | KMS key alias — human-readable reference |
| `backend_config` | Ready-to-paste backend configuration block |

## Configuring the S3 Backend

After deploying the state infrastructure, configure the main project to use it.

### Uncomment backend.tf

Open `terraform/backend.tf` and uncomment the backend block, replacing placeholder values with your outputs:

```hcl
terraform {
  backend "s3" {
    # From: terraform output state_bucket_name
    bucket = "npa-publisher-terraform-state-123456789012"

    # Path within the bucket for this state file
    key = "npa-publishers/terraform.tfstate"

    # Region where the bucket is located
    region = "us-east-1"

    # Enable server-side encryption
    encrypt = true

    # From: terraform output kms_key_arn
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/abc123-..."

    # From: terraform output dynamodb_table_name
    dynamodb_table = "npa-publisher-terraform-lock"
  }
}
```

### Backend Parameters

| Parameter | Required | Description |
|---|---|---|
| `bucket` | Yes | S3 bucket name for state storage |
| `key` | Yes | Path within bucket for the state file |
| `region` | Yes | AWS region of the S3 bucket |
| `encrypt` | Recommended | Enable server-side encryption |
| `kms_key_id` | Recommended | KMS key ARN for encryption |
| `dynamodb_table` | Recommended | DynamoDB table name for locking |

### Environment-Specific Key Paths

Use different `key` paths to maintain separate state for different environments:

```hcl
# Production
key = "npa-publishers/production/terraform.tfstate"

# Staging
key = "npa-publishers/staging/terraform.tfstate"

# Development
key = "npa-publishers/development/terraform.tfstate"
```

All environments can share the same S3 bucket, DynamoDB table, and KMS key. The `key` path provides isolation.

## Migration: Local to Remote

If you already have local state and want to move to S3, Terraform handles the migration automatically.

### Prerequisites

- State infrastructure deployed (see above)
- `backend.tf` configured with your values
- AWS credentials that have access to the S3 bucket, DynamoDB table, and KMS key

### Step-by-Step Migration

**1. Verify current local state:**
```bash
terraform state list
```

This should show your existing resources.

**2. Initialize with the new backend:**
```bash
terraform init -migrate-state
```

Terraform will detect the backend change and prompt:

```
Initializing the backend...
Backend configuration changed!

Terraform has detected that the configuration specified for the backend
has changed. Terraform will now check for existing state in the backends.

Do you want to copy existing state to the new backend?
  Enter a value: yes
```

**3. Type `yes` to confirm the migration.**

Terraform will:
1. Read the local state file
2. Encrypt it with KMS
3. Upload it to S3
4. Acquire a DynamoDB lock during the operation
5. Verify the upload

**4. Verify the migration:**
```bash
# List resources from remote state
terraform state list

# Should show the same resources as before
```

**5. Verify in S3:**
```bash
aws s3 ls s3://npa-publisher-terraform-state-123456789012/npa-publishers/
```

**6. Clean up local state (optional but recommended):**
```bash
# After confirming remote state works
rm terraform.tfstate
rm terraform.tfstate.backup
```

> **Warning**: Only delete local state files after verifying remote state contains all your resources. Run `terraform plan` first to confirm Terraform sees no changes.

### Rollback

If you need to revert to local state:

```bash
# Remove the backend block from backend.tf (comment it out)
terraform init -migrate-state
# Terraform will copy state back to local file
```

## State Security

### Registration Tokens in State

The Netskope publisher registration tokens are stored in Terraform state:

```
netskope_npa_publisher_token.this["my-publisher"]
  ├── publisher_id = "12345"
  └── token        = "eyJhbGciOiJSUz..." (sensitive)
```

**Mitigations:**

1. **Tokens are single-use**: Once a publisher registers with Netskope, the token cannot be reused. An attacker who obtains a used token cannot register additional publishers.

2. **Remote state encryption**: With the S3 backend, state is encrypted at rest with KMS and in transit with HTTPS.

3. **State is not in user data in the CF sense**: Unlike approaches that pass secrets through CloudFormation parameters, the token is embedded in EC2 user data via `templatefile()`. However, user data is visible in EC2 instance metadata and the AWS Console.

4. **IMDSv2 required**: This project requires IMDSv2, which mitigates SSRF attacks that could read instance metadata.

### KMS Encryption

The KMS key created by `terraform/state-infrastructure/` provides:

- **Envelope encryption**: S3 uses a data key derived from your KMS key
- **Key rotation**: Automatic annual rotation of key material
- **Audit trail**: Every encrypt/decrypt operation logged in CloudTrail
- **Access control**: Only IAM principals listed in the key policy can use the key

### S3 Bucket Security

- **Public access blocked**: All four public access block settings enabled
- **HTTPS required**: Bucket policy denies non-SSL requests
- **Versioning enabled**: Previous state versions preserved
- **Access restricted**: Bucket policy limits access to specified IAM ARNs

### IAM Access Control

The state infrastructure uses two layers of IAM access control:

**1. KMS Key Policy** — Controls who can encrypt/decrypt:
```json
{
  "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
  "Principal": { "AWS": ["arn:aws:iam::ACCOUNT:role/TerraformAdmin"] }
}
```

**2. S3 Bucket Policy** — Controls who can read/write state:
```json
{
  "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
  "Principal": { "AWS": ["arn:aws:iam::ACCOUNT:role/TerraformAdmin"] }
}
```

Both must allow access for an operator to use state. This provides defense in depth.

### Audit Trail

Enable CloudTrail to track state access:

```bash
# View recent state access events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=npa-publisher-terraform-state-123456789012 \
  --max-items 20
```

## State Operations

### Listing Resources

```bash
# List all managed resources
terraform state list

# Example output:
# aws_instance.publisher["my-publisher"]
# aws_instance.publisher["my-publisher-2"]
# aws_security_group.publisher
# netskope_npa_publisher.this["my-publisher"]
# netskope_npa_publisher.this["my-publisher-2"]
```

### Showing Resource Details

```bash
# Show a specific resource's attributes
terraform state show 'aws_instance.publisher["my-publisher"]'

# Show Netskope publisher details
terraform state show 'netskope_npa_publisher.this["my-publisher"]'
```

### Importing Existing Resources

If you have existing AWS resources that you want Terraform to manage:

```bash
# Import an existing EC2 instance
terraform import 'aws_instance.publisher["my-publisher"]' i-0123456789abcdef0

# Import an existing VPC
terraform import 'aws_vpc.this[0]' vpc-0123456789abcdef0

# Import an existing security group
terraform import 'aws_security_group.publisher' sg-0123456789abcdef0
```

After importing, run `terraform plan` to verify the configuration matches the imported resource. You may need to update your `.tf` files to match the actual resource configuration.

### Moving Resources in State

Rename a resource without destroying and recreating it:

```bash
# Rename a resource (e.g., after refactoring)
terraform state mv \
  'aws_instance.publisher["old-name"]' \
  'aws_instance.publisher["new-name"]'
```

### Removing Resources from State

Remove a resource from Terraform management without destroying it:

```bash
# Stop managing a resource (resource continues to exist in AWS)
terraform state rm 'aws_instance.publisher["my-publisher"]'
```

> **Warning**: After removing from state, Terraform no longer tracks the resource. You must manage it manually or re-import it.

### Replacing Resources

Force replacement of a specific resource:

```bash
# Replace a specific publisher instance
terraform apply -replace='aws_instance.publisher["my-publisher"]'

# Replace a specific Netskope publisher (re-registers)
terraform apply -replace='netskope_npa_publisher.this["my-publisher"]'
```

This is the Terraform equivalent of "delete and recreate." The resource is destroyed and a new one is created in its place.

### Unlocking State

If a Terraform process crashes or is interrupted, the DynamoDB lock may remain:

```bash
# List current lock (if any)
aws dynamodb get-item \
  --table-name npa-publisher-terraform-lock \
  --key '{"LockID":{"S":"npa-publisher-terraform-state-123456789012/npa-publishers/terraform.tfstate"}}'

# Force unlock (use the LOCK_ID from the error message)
terraform force-unlock LOCK_ID
```

> **Warning**: Only force-unlock when you are certain no other Terraform process is running. Unlocking while another process is active can corrupt state.

## Team Workflow

### How Locking Works

When someone runs `terraform plan` or `terraform apply`, Terraform:

1. Writes a lock record to DynamoDB with the operator's identity
2. If the lock is already held, displays who holds it and when they acquired it
3. Releases the lock when the operation completes (or crashes)

Example lock contention message:
```
Error: Error locking state: Error acquiring the state lock:
  Lock Info:
    ID:        12345678-abcd-...
    Path:      npa-publisher-terraform-state-123456789012/npa-publishers/terraform.tfstate
    Operation: OperationTypeApply
    Who:       alice@workstation
    Version:   1.6.0
    Created:   2025-01-15 10:30:00.123456 +0000 UTC
```

### Concurrent Access Patterns

**Safe pattern — sequential operations:**
```
Alice: terraform plan  → terraform apply → done
                                            Bob: terraform plan → terraform apply → done
```

**Unsafe without locking — concurrent operations:**
```
Alice: terraform plan → terraform apply ─────────→ writes state
Bob:   terraform plan ──→ terraform apply ───────→ writes state (CONFLICT!)
```

With DynamoDB locking, Bob's `terraform apply` would block until Alice's completes.

### CI/CD Considerations

**Pipeline best practices:**

1. **Use the same backend**: CI/CD pipelines should use the same S3 backend as developers
2. **Serialize applies**: Only one pipeline should run `terraform apply` at a time (DynamoDB locking handles this, but queuing is better)
3. **Plan in PR, apply on merge**: Run `terraform plan` on pull requests, `terraform apply` on merge to main
4. **Store plan files**: Save `terraform plan -out=tfplan` and apply the exact plan file

```bash
# In CI/CD pipeline
terraform init
terraform plan -out=tfplan
# (human reviews plan)
terraform apply tfplan
```

**IAM for CI/CD:**

Create a dedicated IAM role for CI/CD with permissions to:
- Access S3 bucket (read/write state)
- Access DynamoDB table (read/write locks)
- Use KMS key (encrypt/decrypt)
- Create/manage the NPA infrastructure resources

See [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md) for details.

### Workspaces

Terraform workspaces provide an alternative to separate `key` paths for environment isolation:

```bash
# Create a workspace
terraform workspace new staging

# Switch workspaces
terraform workspace select production

# List workspaces
terraform workspace list
```

Each workspace maintains its own state file within the same backend. The state key automatically includes the workspace name:

```
s3://bucket/npa-publishers/terraform.tfstate              ← default workspace
s3://bucket/env:/staging/npa-publishers/terraform.tfstate  ← staging workspace
```

> **Note**: For this project, separate `key` paths (as shown in [Configuring the S3 Backend](#configuring-the-s3-backend)) are recommended over workspaces because they are more explicit and easier to manage.

## Disaster Recovery

### Recovering Previous State with S3 Versioning

If state is corrupted or a bad apply occurs, you can recover from S3 versioning:

**1. List state versions:**
```bash
aws s3api list-object-versions \
  --bucket npa-publisher-terraform-state-123456789012 \
  --prefix npa-publishers/terraform.tfstate \
  --query 'Versions[*].[VersionId,LastModified,Size]' \
  --output table
```

**2. Download a previous version:**
```bash
aws s3api get-object \
  --bucket npa-publisher-terraform-state-123456789012 \
  --key npa-publishers/terraform.tfstate \
  --version-id "VERSION_ID_FROM_ABOVE" \
  recovered-state.json
```

**3. Inspect the recovered state:**
```bash
# Check what resources are in the state
python3 -c "
import json
with open('recovered-state.json') as f:
    state = json.load(f)
for r in state.get('resources', []):
    for i in r.get('instances', []):
        print(f\"{r['type']}.{r['name']}[{i.get('index_key', 0)}]\")
"
```

**4. Push the recovered state:**
```bash
# CAUTION: This overwrites current state
terraform state push recovered-state.json
```

### Backup Strategies

**Automatic (recommended):**

S3 versioning is enabled by default in the state-infrastructure module. Every `terraform apply` creates a new version.

**Manual backup:**
```bash
# Pull current state to a local file
terraform state pull > state-backup-$(date +%Y%m%d-%H%M%S).json
```

**Git-based backup for configuration:**
```bash
# Version control your .tf files (never state!)
git add terraform/*.tf
git commit -m "Configuration backup"
```

### Rebuilding with Import

If state is completely lost but infrastructure still exists in AWS, you can rebuild state by importing each resource:

```bash
# Initialize Terraform
terraform init

# Import each resource
terraform import 'aws_vpc.this[0]' vpc-xxxxx
terraform import 'aws_subnet.public[0]' subnet-xxxxx
terraform import 'aws_subnet.public[1]' subnet-xxxxx
terraform import 'aws_subnet.private[0]' subnet-xxxxx
terraform import 'aws_subnet.private[1]' subnet-xxxxx
terraform import 'aws_internet_gateway.this[0]' igw-xxxxx
terraform import 'aws_nat_gateway.this[0]' nat-xxxxx
terraform import 'aws_nat_gateway.this[1]' nat-xxxxx
terraform import 'aws_security_group.publisher' sg-xxxxx
terraform import 'aws_iam_role.publisher' publisher-role
terraform import 'aws_iam_instance_profile.publisher' publisher-profile
terraform import 'aws_instance.publisher["my-publisher"]' i-xxxxx
terraform import 'aws_instance.publisher["my-publisher-2"]' i-xxxxx

# Verify
terraform plan
# Fix any differences between configuration and imported state
```

> **Note**: Netskope resources (`netskope_npa_publisher`, `netskope_npa_publisher_token`) may not support import depending on provider version. Check the [Netskope Terraform Provider documentation](https://registry.terraform.io/providers/netskope/netskope/latest/docs) for current import support.

### Complete Recovery Procedure

If both state and infrastructure are lost:

1. Deploy state infrastructure: `cd terraform/state-infrastructure && terraform apply`
2. Configure backend in `terraform/backend.tf`
3. Initialize: `terraform init`
4. Set variables in `terraform.tfvars` or environment
5. Apply: `terraform apply`

This creates everything from scratch. Netskope publishers will be new registrations.

## Cost

The state infrastructure costs approximately **$1-2/month**:

| Service | Cost | Details |
|---|---|---|
| **KMS Key** | ~$1.00/month | One customer-managed key |
| **S3** | ~$0.01/month | State files are small (typically <1 MB) |
| **DynamoDB** | ~$0.00/month | PAY_PER_REQUEST; lock operations are infrequent |
| **S3 Versioning** | ~$0.01/month | Small incremental storage for versions |

**Total: ~$1.02/month**

The KMS key is the primary cost. All other costs are negligible for state management workloads.

## Additional Resources

- [ARCHITECTURE.md](ARCHITECTURE.md) — Architecture overview including state backend
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — Deployment paths including remote state setup
- [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md) — IAM permissions for state access
- [Terraform S3 Backend Documentation](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [Terraform State Documentation](https://developer.hashicorp.com/terraform/language/state)
