# Terraform Technical Notes

Technical deep-dive into the Terraform patterns, Netskope provider integration, and development tooling used in this project.

## Table of Contents

- [Netskope Terraform Provider](#netskope-terraform-provider)
- [Publisher Registration Flow](#publisher-registration-flow)
- [for_each Pattern](#for_each-pattern)
- [Conditional Resource Creation](#conditional-resource-creation)
- [User Data Template and SSM Registration](#user-data-template)
- [IAM Configuration](#iam-configuration)
- [Pre-commit Hooks and Code Quality](#pre-commit-hooks-and-code-quality)
- [Lifecycle Rules](#lifecycle-rules)
- [Provider Version Constraints](#provider-version-constraints)

## Netskope Terraform Provider

### Provider Configuration

The Netskope provider is configured in `terraform/providers.tf`:

```hcl
provider "netskope" {
  server_url = var.netskope_server_url
  api_key    = var.netskope_api_key
}
```

### Authentication

The provider authenticates using a REST API v2 token. The recommended approach is environment variables:

```bash
export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
export TF_VAR_netskope_api_key="your-api-key"
```

The API key requires the **Infrastructure Management** scope in Netskope:
1. Netskope UI → **Settings → Tools → REST API v2**
2. Create or select a token
3. Enable **Infrastructure Management** (read/write)

### Resources Used

| Resource | File | Purpose |
|---|---|---|
| `netskope_npa_publisher` | `terraform/netskope.tf` | Creates publisher records in Netskope tenant |
| `netskope_npa_publisher_token` | `terraform/netskope.tf` | Generates one-time registration tokens |

### API Calls During Apply

When `terraform apply` runs, the Netskope provider makes these API calls:

1. **Create publisher**: `POST /api/v2/infrastructure/publishers`
   - Creates a named publisher record
   - Returns publisher ID

2. **Generate token**: `POST /api/v2/infrastructure/publishers/{id}/token` (or equivalent)
   - Generates a registration token for the publisher
   - Token is single-use

3. **Read publisher** (during plan/refresh): `GET /api/v2/infrastructure/publishers/{id}`
   - Reads current publisher state for comparison

4. **Delete publisher** (during destroy): `DELETE /api/v2/infrastructure/publishers/{id}`
   - Removes publisher from Netskope tenant

> **Note**: The Netskope API must be reachable from wherever Terraform runs (operator workstation or CI/CD). This is different from the CloudFormation approach where Lambda runs inside the VPC.

## Publisher Registration Flow

The end-to-end flow from Terraform to a connected publisher:

```
1. Terraform creates netskope_npa_publisher
   └─ API call to Netskope → publisher record created

2. Terraform creates netskope_npa_publisher_token
   └─ API call to Netskope → registration token generated

3. Terraform stores token in SSM Parameter Store (SecureString)
   └─ aws_ssm_parameter.publisher_token (encrypted at rest with KMS)

4. Terraform creates aws_instance with minimal user data
   └─ EC2 instance launches in private subnet
   └─ User data only installs CloudWatch agent (if enabled)

5. null_resource.publisher_registration polls SSM
   └─ Waits for instance to appear as "Online" in SSM
   └─ Confirms SSM agent is running and network is ready

6. Terraform fetches token locally from SSM Parameter Store
   └─ aws ssm get-parameter (runs on operator workstation)

7. Terraform sends registration command via SSM Run Command
   └─ aws ssm send-command → /home/ubuntu/npa_publisher_wizard -token <TOKEN>
   └─ Waits for command completion and checks status

8. Publisher wizard registers with Netskope
   └─ Token consumed (single-use)
   └─ Outbound TLS connection to NewEdge established

9. Publisher appears as "Connected" in Netskope UI
```

### Security Implications

**Token in SSM Parameter Store:**

The registration token is stored as a SecureString in SSM Parameter Store (encrypted at rest with KMS). It is delivered to the instance via SSM Run Command (encrypted channel). This means:
- The token is **not** visible in EC2 user data or instance metadata
- The token is encrypted at rest in SSM Parameter Store
- The token is stored in Terraform state (encrypted with KMS if using remote state)
- SSM Run Command delivers the token over an encrypted channel

**Mitigations:**
- **Single-use token**: Once the publisher registers, the token cannot be reused
- **SSM encrypted delivery**: Token is never embedded in user data or instance metadata
- **IMDSv2 required**: This project enforces IMDSv2, which requires session tokens and mitigates SSRF attacks
- **State encryption**: Remote state is encrypted with KMS
- **No SSH access needed**: Use SSM Session Manager instead of SSH keys
- **IAM-controlled access**: Only the publisher instance role can read its own token from SSM

**Comparison with CloudFormation approach:**

The CloudFormation version stores the API token in AWS Secrets Manager and delivers the registration token via SSM Run Command. This Terraform approach now follows a similar pattern — tokens are stored in SSM Parameter Store (SecureString) and delivered via SSM Run Command. The main difference is that Terraform uses a `null_resource` with `local-exec` provisioners to orchestrate the SSM polling and command execution, whereas CloudFormation uses a Lambda function.

## for_each Pattern

### The publishers Local

The `local.publishers` map is the core of the multi-instance pattern:

```hcl
# terraform/locals.tf
locals {
  publishers = {
    for i in range(var.publisher_count) :
    (i == 0 ? var.publisher_name : "${var.publisher_name}-${i + 1}") => {
      index = i
      name  = i == 0 ? var.publisher_name : "${var.publisher_name}-${i + 1}"
    }
  }
}
```

With `publisher_name = "my-pub"` and `publisher_count = 3`, this generates:

```hcl
{
  "my-pub"   = { index = 0, name = "my-pub" }
  "my-pub-2" = { index = 1, name = "my-pub-2" }
  "my-pub-3" = { index = 2, name = "my-pub-3" }
}
```

### State Addressing

Resources using `for_each` are addressed by their map key:

```
netskope_npa_publisher.this["my-pub"]
netskope_npa_publisher.this["my-pub-2"]
netskope_npa_publisher.this["my-pub-3"]

aws_instance.publisher["my-pub"]
aws_instance.publisher["my-pub-2"]
aws_instance.publisher["my-pub-3"]
```

### Why for_each Over count

**The count problem:**
```hcl
# With count, resources are indexed by position:
resource "aws_instance" "publisher" {
  count = 3
  # aws_instance.publisher[0], [1], [2]
}

# Removing index 1 shifts everything:
# [0] stays, [1] becomes the OLD [2], [2] is destroyed
# This destroys and recreates the wrong instance!
```

**The for_each solution:**
```hcl
# With for_each, resources are indexed by name:
resource "aws_instance" "publisher" {
  for_each = local.publishers
  # aws_instance.publisher["my-pub"], ["my-pub-2"], ["my-pub-3"]
}

# Removing "my-pub-2" only affects that specific resource:
# ["my-pub"] stays, ["my-pub-2"] is destroyed, ["my-pub-3"] stays
```

### Adding/Removing Publishers

**Add a publisher** — increase `publisher_count`:
```bash
# terraform.tfvars
publisher_count = 3  # Was 2

terraform apply
# Only creates: aws_instance.publisher["my-pub-3"]
# Existing instances untouched
```

**Remove a publisher** — decrease `publisher_count`:
```bash
# terraform.tfvars
publisher_count = 1  # Was 2

terraform apply
# Only destroys: aws_instance.publisher["my-pub-2"]
# Existing instance untouched
```

### AZ Distribution

Instances are distributed across availability zones using modulo arithmetic:

```hcl
subnet_id = local.private_subnet_ids[each.value.index % length(local.private_subnet_ids)]
```

With 2 subnets and 4 publishers:
| Publisher | Index | Index % 2 | Subnet |
|---|---|---|---|
| my-pub | 0 | 0 | private-subnet-az1 |
| my-pub-2 | 1 | 1 | private-subnet-az2 |
| my-pub-3 | 2 | 0 | private-subnet-az1 |
| my-pub-4 | 3 | 1 | private-subnet-az2 |

## Conditional Resource Creation

### count for On/Off Toggles

The project uses `count` with 0 or 1 for optional resources:

**VPC resources (create or use existing):**
```hcl
resource "aws_vpc" "this" {
  count = var.create_vpc ? 1 : 0
  # Created if create_vpc = true, skipped if false
}
```

**CloudWatch monitoring (optional feature):**
```hcl
resource "aws_ssm_parameter" "cloudwatch_config" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  # Created only when monitoring is enabled
}
```

**AMI data source (skip if AMI provided):**
```hcl
data "aws_ami" "netskope_publisher" {
  count = var.publisher_ami_id == "" ? 1 : 0
  # Only queries AWS Marketplace if no AMI ID was provided
}
```

### Accessing count-Based Resources

Resources created with `count` are lists, requiring `[0]` indexing:

```hcl
# Direct access
local.vpc_id = var.create_vpc ? aws_vpc.this[0].id : var.existing_vpc_id

# Splat expression for lists
local.private_subnet_ids = var.create_vpc ? aws_subnet.private[*].id : var.existing_private_subnet_ids
```

### Ternary Patterns

Common ternary patterns in this project:

```hcl
# Select created or existing resource
local.vpc_id = var.create_vpc ? aws_vpc.this[0].id : var.existing_vpc_id

# Select provided or auto-detected value
local.publisher_ami_id = var.publisher_ami_id != "" ? var.publisher_ami_id : data.aws_ami.netskope_publisher[0].id

# Select provided or auto-discovered AZs
local.azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

# Conditional string (empty if feature disabled)
cloudwatch_config_parameter = var.enable_cloudwatch_monitoring ? aws_ssm_parameter.cloudwatch_config[0].name : ""
```

## User Data Template

### Template File

The user data script is in `terraform/templates/userdata.tftpl`. It is minimal — publisher registration is handled separately via SSM Run Command after the instance is confirmed online:

```bash
#!/bin/bash
set -e

%{ if enable_cloudwatch ~}
echo "Installing CloudWatch agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c ssm:${cloudwatch_config_parameter}
echo "CloudWatch agent installed and configured"
%{ endif ~}
```

### Template Rendering

The template is rendered using `templatefile()`:

```hcl
user_data = base64encode(templatefile("${path.module}/templates/userdata.tftpl", {
  enable_cloudwatch           = var.enable_cloudwatch_monitoring
  cloudwatch_config_parameter = var.enable_cloudwatch_monitoring ? aws_ssm_parameter.cloudwatch_config[0].name : ""
}))
```

### SSM-Based Registration

Publisher registration is handled by `null_resource.publisher_registration` in `ec2_publisher.tf`, which uses two `local-exec` provisioners:

**Step 1 — Wait for SSM readiness:**
```bash
# Polls aws ssm describe-instance-information until the instance is "Online"
# Max 40 attempts × 15s = 10 minutes
```

**Step 2 — Register via SSM Run Command:**
```bash
# Fetches token LOCALLY from SSM Parameter Store (operator workstation)
TOKEN=$(aws ssm get-parameter --name "/npa/publishers/<name>/registration-token" \
  --with-decryption --query "Parameter.Value" --output text ...)

# Sends registration command to the instance via SSM Run Command
aws ssm send-command --instance-ids "<id>" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="[\"/home/ubuntu/npa_publisher_wizard -token $TOKEN\"]" ...
```

This approach is more reliable than user data because:
- Terraform waits for the instance and network to be fully ready
- Registration output is captured in SSM command history
- Failures are visible in the `terraform apply` output
- No dependency on NAT Gateway timing during cloud-init

### Template Syntax

| Syntax | Purpose | Example |
|---|---|---|
| `${var}` | Variable interpolation | `${cloudwatch_config_parameter}` |
| `%{ if cond ~}` | Conditional block start | `%{ if enable_cloudwatch ~}` |
| `%{ endif ~}` | Conditional block end | `%{ endif ~}` |
| `~` | Strip whitespace | Prevents blank lines in output |

### base64encode

EC2 user data must be base64-encoded. The `base64encode()` function handles this:

```hcl
user_data = base64encode(templatefile(...))
```

Without `base64encode()`, Terraform would pass raw text, and AWS would reject it.

## IAM Configuration

### Instance Role Pattern

The project follows the standard EC2 IAM pattern:

```
aws_iam_role.publisher
  └─► aws_iam_instance_profile.publisher
        └─► aws_instance.publisher (iam_instance_profile)
```

**Why three resources?**
- **Role**: Defines the IAM identity and trust policy
- **Instance Profile**: Wrapper that allows EC2 to assume the role (EC2 cannot use roles directly)
- **Instance**: References the instance profile

### Trust Policy

The role's trust policy allows EC2 to assume it:

```hcl
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Action = "sts:AssumeRole"
    Effect = "Allow"
    Principal = {
      Service = "ec2.amazonaws.com"
    }
  }]
})
```

### Policy Attachments

Policies are attached as separate resources (not inline):

```hcl
# Always attached — SSM agent needs this
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.publisher.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy — read registration tokens from SSM Parameter Store
resource "aws_iam_role_policy" "publisher_token_access" {
  name   = "publisher-token-access"
  role   = aws_iam_role.publisher.id
  policy = data.aws_iam_policy_document.publisher_token_access.json
}

# Conditionally attached — only when monitoring enabled
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count      = var.enable_cloudwatch_monitoring ? 1 : 0
  role       = aws_iam_role.publisher.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

## Pre-commit Hooks and Code Quality

### Hook Configuration

The `.pre-commit-config.yaml` defines three categories of hooks:

#### Terraform Hooks (pre-commit-terraform)

| Hook | Command | Purpose |
|---|---|---|
| `terraform_fmt` | `terraform fmt` | Consistent code formatting |
| `terraform_validate` | `terraform validate` | Syntax and configuration validation |
| `terraform_docs` | `terraform-docs` | Auto-generate README from variables/outputs |
| `terraform_tflint` | `tflint` | Linting and best practice enforcement |
| `terraform_tfsec` | `tfsec` | Security vulnerability scanning |
| `terraform_checkov` | `checkov` | Compliance and misconfiguration detection |

#### General Hooks (pre-commit-hooks)

| Hook | Purpose |
|---|---|
| `check-added-large-files` | Prevent files > 1000 KB |
| `check-case-conflict` | Detect case-sensitive filename conflicts |
| `check-merge-conflict` | Detect unresolved merge markers |
| `end-of-file-fixer` | Ensure files end with newline |
| `trailing-whitespace` | Remove trailing whitespace |
| `check-yaml` | Validate YAML syntax |
| `check-json` | Validate JSON syntax |
| `detect-aws-credentials` | Prevent committing AWS credentials |
| `detect-private-key` | Prevent committing private keys |

#### Secrets Detection (gitleaks)

Scans all staged files for patterns matching known secret formats (API keys, tokens, passwords).

### Installation and Usage

```bash
# Install pre-commit
pip install pre-commit

# Install hooks in the repository
pre-commit install

# Run manually on all files
pre-commit run --all-files

# Run a specific hook
pre-commit run terraform_fmt --all-files
pre-commit run terraform_tfsec --all-files
```

### TFLint Configuration

The `.tflint.hcl` file configures the linter with:

- **AWS plugin** (v0.31.0): AWS-specific rules for instance types, AMIs, IAM
- **Terraform plugin**: Recommended preset for naming, documentation, versioning
- Custom rules for variable descriptions, output descriptions, naming conventions

### terraform-docs Configuration

The `.terraform-docs.yaml` configures auto-documentation:

- Output format: Markdown table
- Target file: `README.md` (inject mode)
- Sections: requirements, providers, modules, resources, inputs, outputs
- Includes default values, type information, and descriptions

## Lifecycle Rules

### ignore_changes

The EC2 instances use `ignore_changes` to prevent unintended replacements:

```hcl
lifecycle {
  ignore_changes = [ami, user_data]
}
```

**Why ignore AMI changes?**
- New AMIs are released regularly
- Without `ignore_changes`, Terraform would want to replace instances on every `terraform plan` if a newer AMI exists
- Publishers should be updated via Netskope auto-updates, not AMI replacement

**Why ignore user_data changes?**
- User data changes force instance replacement (destroy + recreate)
- Existing publishers should not be disrupted

### Intentional Replacement

When you do want to replace an instance (e.g., to apply a new AMI), you must also replace the Netskope publisher record and token because registration tokens are single-use:

```bash
# Replace a specific publisher (all three resources)
terraform apply \
  -replace='netskope_npa_publisher.this["my-publisher"]' \
  -replace='netskope_npa_publisher_token.this["my-publisher"]' \
  -replace='aws_instance.publisher["my-publisher"]'
```

### When to Use -replace

| Scenario | Command |
|---|---|
| Instance is unhealthy | `terraform apply -replace='netskope_npa_publisher.this["name"]' -replace='netskope_npa_publisher_token.this["name"]' -replace='aws_instance.publisher["name"]'` |
| Need fresh AMI | Same as above (new instance needs new token) |
| Re-run registration only | `terraform apply -replace='null_resource.publisher_registration["name"]'` |
| Replace everything | `terraform destroy && terraform apply` |

## Provider Version Constraints

### Version Specification

From `terraform/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    netskope = {
      source  = "netskopeoss/netskope"
      version = ">= 0.3.3"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}
```

### Version Constraint Syntax

| Constraint | Meaning |
|---|---|
| `>= 1.0` | Version 1.0 or later |
| `~> 5.0` | Version 5.x (any minor/patch, not 6.0) |
| `= 5.30.0` | Exactly version 5.30.0 |

### Lock File

The `.terraform.lock.hcl` file pins exact provider versions and checksums. It ensures all team members and CI/CD use identical provider versions.

```bash
# Update lock file after changing version constraints
terraform init -upgrade
```

> **Note**: The lock file is excluded from pre-commit hooks (see `.pre-commit-config.yaml`).

## Additional Resources

- [ARCHITECTURE.md](ARCHITECTURE.md) — Architecture overview
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) — State management guide
- [OPERATIONS.md](OPERATIONS.md) — Day-2 operations
- [Netskope Terraform Provider](https://registry.terraform.io/providers/netskope/netskope/latest/docs)
- [Terraform for_each Documentation](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)
- [pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform)
