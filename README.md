# NPA Publisher - Multi-AZ Deployment (Terraform)

Automated deployment of Netskope Private Access (NPA) Publishers using Terraform with multi-AZ redundancy and the Netskope Terraform provider for publisher lifecycle management.

## Overview

This solution provides a highly available deployment of NPA Publishers with automatic registration to your Netskope tenant. It uses the [Netskope Terraform provider](https://registry.terraform.io/providers/netskopeoss/netskope/latest) to create publishers, generate registration tokens, and launch EC2 instances that self-register on boot. Multi-AZ deployment distributes publishers across availability zones for production redundancy.

## Documentation

This project includes comprehensive documentation for deployment, operations, and troubleshooting:

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** — Detailed architecture overview covering network design, security layers, high availability, and AWS Well-Architected Framework alignment
- **[QUICKSTART.md](docs/QUICKSTART.md)** — Get started with a guided quick deployment
- **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** — Complete deployment instructions with all configuration options and multiple deployment paths
- **[STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md)** — Terraform state management: local vs. remote, S3 backend setup, migration, security, and disaster recovery
- **[IAM_PERMISSIONS.md](docs/IAM_PERMISSIONS.md)** — Required IAM permissions for the Terraform operator, with full policy JSON and CI/CD examples
- **[DEVOPS-NOTES.md](docs/DEVOPS-NOTES.md)** — Technical deep-dive into Terraform patterns, provider internals, `for_each`, user data, pre-commit hooks, and Terratest
- **[OPERATIONS.md](docs/OPERATIONS.md)** — Day-2 operational procedures: upgrades, scaling, rotation, replacement, and monitoring
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — Common issues and solutions with diagnostic commands

**Quick Links:**
- Want to understand the architecture? See **[ARCHITECTURE.md](docs/ARCHITECTURE.md)**
- New to the project? Start with **[QUICKSTART.md](docs/QUICKSTART.md)**
- Need to deploy? See **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)**
- Setting up remote state? See **[STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md)**
- Already deployed? Check **[OPERATIONS.md](docs/OPERATIONS.md)**
- Having issues? See **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**

## IAM Permissions Required

To deploy this Terraform configuration, the operator needs permissions to create and manage multiple AWS resources. A complete IAM policy is provided in **[IAM_PERMISSIONS.md](docs/IAM_PERMISSIONS.md)**.

### Permission Summary

| Service | Key Permissions | Purpose |
|---------|----------------|---------|
| **EC2** | VPC, subnets, NAT gateways, security groups, instances | Network infrastructure and compute |
| **IAM** | Create/manage roles and instance profiles | EC2 instance roles for SSM |
| **SSM** | Describe instances, start sessions | Publisher management via Session Manager |
| **S3** | Create/manage buckets | Terraform state storage (remote backend) |
| **DynamoDB** | Create/manage tables | Terraform state locking (remote backend) |
| **KMS** | Create/manage keys | State encryption at rest |
| **CloudWatch** | Create log groups, put metrics | Optional monitoring |

### Least Privilege Considerations

- IAM role permissions are scoped to resources with the publisher name prefix
- S3 and DynamoDB permissions are limited to state backend resources
- No `*:*` permissions are granted
- See **[IAM_PERMISSIONS.md](docs/IAM_PERMISSIONS.md)** for the full policy JSON and setup instructions

## VPC Deployment Options

The configuration supports two deployment modes:

### Option 1: Create New VPC

- **Automatically creates**: VPC, Internet Gateway, NAT Gateways (2), public and private subnets (2 AZs)
- **Routing**: Configured automatically for redundant internet access
- **High availability**: Multi-AZ deployment with redundant NAT Gateways

```hcl
create_vpc           = true
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.2.0/24", "10.0.4.0/24"]
availability_zones   = []  # Auto-select first 2 available AZs
```

### Option 2: Use Existing VPC

- **Requires**: Existing VPC with private subnets that have NAT Gateway routes
- **DNS**: VPC must have DNS hostnames and DNS support enabled

```hcl
create_vpc                  = false
existing_vpc_id             = "vpc-0123456789abcdef0"
existing_private_subnet_ids = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Terraform Operator                                                 │
│  terraform plan / apply / destroy                                   │
└────────┬───────────────────────────────────┬────────────────────────┘
         │                                   │
         ▼                                   ▼
┌─────────────────────┐           ┌─────────────────────────┐
│  Netskope API       │           │  AWS API                │
│  Create publishers  │           │  Create infrastructure  │
│  Generate tokens    │           │                         │
└─────────────────────┘           └────────┬────────────────┘
                                           │
                                           ▼
                              ┌────────────────────────┐
                              │  VPC (10.0.0.0/16)     │
                              │                        │
                              │  ┌──────────────────┐  │
                              │  │ Private Subnets   │  │
                              │  │                   │  │
                              │  │  ┌─────────────┐  │  │
                              │  │  │ Publisher 1  │──┼──┼──▶ Netskope NewEdge
                              │  │  │ (AZ 1)      │  │  │
                              │  │  └─────────────┘  │  │
                              │  │  ┌─────────────┐  │  │
                              │  │  │ Publisher 2  │──┼──┼──▶ Netskope NewEdge
                              │  │  │ (AZ 2)      │  │  │
                              │  │  └─────────────┘  │  │
                              │  └────────┬─────────┘  │
                              │           │            │
                              │           ▼            │
                              │  ┌──────────────────┐  │
                              │  │ Public Subnets    │  │
                              │  │ NAT GW 1 │ NAT 2 │  │
                              │  └──────────────────┘  │
                              └────────────────────────┘
```

## Security Group Requirements

The NPA Publisher instances require specific outbound access. No inbound rules are needed — publishers only initiate outbound connections.

### Egress Rules

| Rule | Port | Protocol | Destination | Purpose |
|------|------|----------|-------------|---------|
| HTTPS | 443 | TCP | `0.0.0.0/0` | Netskope registration and tunnel endpoints |
| DNS | 53 | UDP | `0.0.0.0/0` | Hostname resolution |
| NewEdge DC | 443 | TCP | See below | Netskope data plane |
| RFC1918 | All | All | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | Private app discovery |

### Netskope NewEdge IP Ranges

| CIDR Block | Description |
|------------|-------------|
| `8.36.116.0/24` | NewEdge Data Center |
| `8.39.144.0/24` | NewEdge Data Center |
| `31.186.239.0/24` | NewEdge Data Center |
| `163.116.128.0/17` | NewEdge Data Center |
| `162.10.0.0/17` | NewEdge Data Center |

> **Note**: The security group currently allows all outbound HTTPS (`0.0.0.0/0`) as a temporary workaround. Netskope NPA registration endpoints use AWS-hosted IPs not included in the documented NewEdge ranges. Contact Netskope support for the complete list before restricting egress in production.

## How It Works

### On `terraform apply`

1. **Netskope provider creates publishers** in your Netskope tenant via the REST API
2. **Netskope provider generates registration tokens** (one per publisher, single-use)
3. **Terraform creates EC2 instances** with user data containing the registration token
4. **EC2 instances boot** and execute the user data script
5. **`npa_publisher_wizard`** runs on each instance, consuming the token and establishing an outbound TLS connection to Netskope NewEdge
6. **Publishers appear as "Connected"** in the Netskope admin console

### On `terraform destroy`

Terraform enforces correct destroy ordering via explicit dependencies:

1. **EC2 instances terminated first** — disconnects publishers from Netskope
2. **Registration tokens removed** from state
3. **Publisher records deleted** from Netskope via the API (succeeds because instances are already gone)

## Getting Started

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- Netskope API key with **Infrastructure Management** scope
- EC2 key pair in the target region
- [Netskope Publisher AMI](https://aws.amazon.com/marketplace) subscription

### Quick Deploy

```bash
# 1. Clone and configure
git clone <repository-url>
cd AWS-NPA-Ref-Architecture-Terraform/terraform
cp example.tfvars terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Set Netskope credentials
export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"
export TF_VAR_netskope_api_key="your-api-key"

# 3. Deploy
terraform init
terraform plan
terraform apply

# 4. Verify
terraform output publisher_names
terraform output publisher_private_ips
# Check Netskope UI: Settings → Security Cloud Platform → Publishers → verify "Connected"
```

For detailed instructions, see **[QUICKSTART.md](docs/QUICKSTART.md)** or **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)**.

## Project Structure

```
AWS-NPA-Ref-Architecture-Terraform/
├── README.md                        # This file
├── LICENSE                          # BSD 3-Clause License
├── CLAUDE.md                        # Project guidelines for AI-assisted development
│
├── docs/                            # Comprehensive documentation
│   ├── ARCHITECTURE.md
│   ├── QUICKSTART.md
│   ├── DEPLOYMENT_GUIDE.md
│   ├── STATE_MANAGEMENT.md
│   ├── IAM_PERMISSIONS.md
│   ├── DEVOPS-NOTES.md
│   ├── OPERATIONS.md
│   └── TROUBLESHOOTING.md
│
├── terraform/                       # All Terraform code
│   ├── main.tf                      # AWS provider default tags
│   ├── variables.tf                 # Input variables with validation
│   ├── outputs.tf                   # Output values (IDs, IPs, names)
│   ├── providers.tf                 # AWS and Netskope provider configuration
│   ├── versions.tf                  # Terraform and provider version constraints
│   ├── backend.tf                   # S3 remote state backend (commented template)
│   ├── data.tf                      # Data sources (region, caller identity)
│   ├── locals.tf                    # Computed values (publisher map, AMI, AZ selection)
│   │
│   ├── netskope.tf                  # Netskope publisher and token resources
│   ├── ec2_publisher.tf             # EC2 instances with for_each distribution
│   ├── vpc.tf                       # VPC, subnets, NAT gateways, routing
│   ├── security.tf                  # Security group with egress rules
│   ├── iam.tf                       # IAM role, instance profile, policy attachments
│   ├── ssm.tf                       # CloudWatch agent SSM parameter (optional)
│   │
│   ├── example.tfvars               # Example variable values (copy to terraform.tfvars)
│   ├── templates/
│   │   └── userdata.tftpl           # EC2 user data template (registration + CloudWatch)
│   │
│   ├── state-infrastructure/        # Separate module for S3/DynamoDB/KMS state backend
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── examples/
│   │   └── basic/                   # Basic usage example
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars.example
│   │
│
├── .pre-commit-config.yaml          # Pre-commit hooks (fmt, validate, tfsec, checkov)
├── .terraform-docs.yaml             # terraform-docs configuration
├── .tflint.hcl                      # TFLint configuration
└── .gitignore                       # Git ignore rules
```

## Cost Estimation

Approximate monthly costs for us-east-1 region (2 publishers, new VPC):

| Resource | Monthly Cost |
|----------|-------------|
| EC2 t3.large x2 (24/7) | ~$120 |
| NAT Gateway x2 | ~$64 + data transfer |
| VPC Endpoints x3 (SSM) | ~$22 |
| EBS gp3 30GB x2 | ~$5 |
| State backend (S3 + DynamoDB + KMS) | ~$1 |
| CloudWatch custom metrics (optional) | ~$5 |
| **Total (new VPC)** | **~$212/month** |
| **Total (existing VPC)** | **~$125/month** |

*Costs vary by region, instance type, and data transfer volume.*

> Compared to the CloudFormation reference architecture, this Terraform deployment costs less because it does not require Lambda functions or Secrets Manager.

## Security Considerations

- **No inbound rules** — Publishers only initiate outbound connections
- **IMDSv2 enforced** — Instance metadata requires session tokens (SSRF protection)
- **Encrypted volumes** — EBS root volumes encrypted at rest
- **No public IPs** — Instances deployed in private subnets only
- **SSM Session Manager** — No SSH bastion or key distribution needed
- **State encryption** — Remote state encrypted with KMS (when using S3 backend)
- **Pre-commit scanning** — tfsec, checkov, and gitleaks catch issues before commit

> **Trade-off**: Registration tokens are embedded in EC2 user data, which is stored in Terraform state and visible in EC2 instance metadata. Tokens are single-use and expire, but the state file should be treated as sensitive. See **[STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md)** for encryption and access control guidance.

## Limitations

- No auto scaling — fixed capacity per deployment
- Instance failure requires manual replacement (`terraform apply -replace`)
- Registration tokens are single-use — replacing an instance generates a new token
- Publishers self-update, but AMI changes require instance replacement

## Use Cases

**Ideal for:**
- Production workloads with predictable traffic patterns
- Multi-AZ redundancy requirements
- Teams using Terraform for infrastructure management
- Organizations with existing S3/DynamoDB state backends

**Built-in redundancy:**
- Multi-AZ deployment (configurable 1-10 publishers across available AZs)
- Redundant NAT Gateways (one per AZ)
- `for_each` instance management prevents cascading state changes

**Considerations for production:**
- Monitor publisher health in Netskope admin console
- Use remote state with encryption and locking for team environments
- Configure CloudWatch monitoring for memory and disk metrics

## Additional Resources

### Project Documentation
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** — Architecture overview and AWS best practices
- **[QUICKSTART.md](docs/QUICKSTART.md)** — Quick deployment guide
- **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** — Complete deployment instructions
- **[STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md)** — State management and recovery
- **[IAM_PERMISSIONS.md](docs/IAM_PERMISSIONS.md)** — Required IAM permissions
- **[DEVOPS-NOTES.md](docs/DEVOPS-NOTES.md)** — Technical deep-dive
- **[OPERATIONS.md](docs/OPERATIONS.md)** — Operational procedures
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — Common issues and solutions

### External Resources
- [Netskope REST API v2](https://docs.netskope.com/en/rest-api-v2-overview-312207.html)
- [Netskope Terraform Provider](https://registry.terraform.io/providers/netskopeoss/netskope/latest)
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [NewEdge IP Ranges](https://docs.netskope.com/en/newedge-ip-ranges-for-allowlisting)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

## License

BSD 3-Clause License. See [LICENSE](LICENSE) for details.
