# Architecture Overview

AWS reference architecture for deploying Netskope Private Access (NPA) Publishers using Terraform. This document explains each design decision through the lens of AWS best practices and the [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html).

## Table of Contents

- [Architecture Diagram](#architecture-diagram)
- [Component Overview](#component-overview)
- [Network Architecture](#network-architecture)
- [Security Architecture](#security-architecture)
- [High Availability Design](#high-availability-design)
- [Additional Resources](#additional-resources)

## Architecture Diagram

```
                                                       ┌──────────────────────────┐
                                                       │  Terraform Operator      │
                                                       │  (Workstation / CI/CD)   │
                                                       └────────────┬─────────────┘
                                                                    │
                                                                    │ Terraform API Calls
                                                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                      │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    AWS Services                                       │  │
│  │                                                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │     IAM      │  │   Systems   │  │  CloudWatch  │               │  │
│  │  │  (Instance   │  │   Manager   │  │    (Logs &   │               │  │
│  │  │   Profile)   │  │  (Session   │  │   Metrics)   │               │  │
│  │  │              │  │   Manager)  │  │              │               │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │               Terraform State Backend (Optional)                      │  │
│  │                                                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │   S3 Bucket  │  │   DynamoDB   │  │   KMS Key    │               │  │
│  │  │ (State File) │  │  (Locking)   │  │ (Encryption) │               │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                                  │  │
│  │                                                                       │  │
│  │  ┌──────────────────────┐         ┌──────────────────────┐           │  │
│  │  │  Availability Zone 1 │         │  Availability Zone 2 │           │  │
│  │  │                      │         │                      │           │  │
│  │  │  ┌────────────────┐  │         │  ┌────────────────┐  │           │  │
│  │  │  │ Private Subnet │  │         │  │ Private Subnet │  │           │  │
│  │  │  │ 10.0.2.0/24    │  │         │  │ 10.0.4.0/24    │  │           │  │
│  │  │  │                │  │         │  │                │  │           │  │
│  │  │  │ ┌────────────┐ │  │         │  │ ┌────────────┐ │  │           │  │
│  │  │  │ │    NPA     │ │  │         │  │ │    NPA     │ │  │           │  │
│  │  │  │ │ Publisher  │ │  │         │  │ │ Publisher  │ │  │           │  │
│  │  │  │ │ Instance 1 │ │  │         │  │ │ Instance 2 │ │  │           │  │
│  │  │  │ └────────────┘ │  │         │  │ └────────────┘ │  │           │  │
│  │  │  └────────┬───────┘  │         │  └────────┬───────┘  │           │  │
│  │  │           │          │         │           │          │           │  │
│  │  │  ┌────────▼───────┐  │         │  ┌────────▼───────┐  │           │  │
│  │  │  │ Public Subnet  │  │         │  │ Public Subnet  │  │           │  │
│  │  │  │ 10.0.1.0/24    │  │         │  │ 10.0.3.0/24    │  │           │  │
│  │  │  │                │  │         │  │                │  │           │  │
│  │  │  │  NAT Gateway   │  │         │  │  NAT Gateway   │  │           │  │
│  │  │  └────────────────┘  │         │  └────────────────┘  │           │  │
│  │  └──────────────────────┘         └──────────────────────┘           │  │
│  │           │                                    │                      │  │
│  │           └────────────────┬───────────────────┘                      │  │
│  │                            │                                          │  │
│  └────────────────────────────┼──────────────────────────────────────────┘  │
│                               │                                             │
│                               │ Internet Gateway                            │
│                               ▼                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                │ HTTPS 443
                                ▼
                 ┌───────────────────────────────┐
                 │  Netskope NewEdge Network     │
                 │  (Publisher Management)       │
                 └───────────────────────────────┘
```

## Component Overview

### VPC and Subnet Design

**AWS best practice**: Place workloads in private subnets unless they require direct inbound internet access ([VPC User Guide — VPC with public and private subnets](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Scenario2.html)).

- **VPC** (10.0.0.0/16, configurable): Isolated network environment with DNS support enabled. Only created when `create_vpc = true`; an existing VPC can be supplied instead.
- **Private Subnets** (10.0.2.0/24, 10.0.4.0/24): Host NPA Publisher EC2 instances. No public IP addresses. Egress via NAT Gateway.
- **Public Subnets** (10.0.1.0/24, 10.0.3.0/24): Host NAT Gateways only — no compute resources. Route to internet via Internet Gateway.

### NAT Gateways

**AWS best practice**: Deploy one NAT Gateway per Availability Zone so that resources in each AZ are not dependent on another AZ's gateway ([REL02-BP02](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_planning_horizontal_scaling.html)).

- Two NAT Gateways, one per AZ, each with a static Elastic IP
- Zone-isolated failure domains: an AZ1 NAT Gateway failure does not affect AZ2
- Managed service with automatic scaling and 99.99% SLA

### EC2 Instances (NPA Publishers)

**AWS best practice**: Use instance profiles for credential management instead of long-lived keys ([SEC02-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_unique.html)). Require IMDSv2 to prevent SSRF-based credential theft ([SEC06-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_compute_vulnerability_management.html)).

- **Instance type**: t3.large (default, configurable)
- **AMI**: Netskope Private Access Publisher (AWS Marketplace)
- **Deployment**: Distributed across AZs using `for_each` with modulo distribution
- **Networking**: Private subnet placement (no public IP)
- **IAM**: Instance profile with Systems Manager permissions only
- **IMDS**: v2 required (session tokens for SSRF protection)
- **Storage**: 30 GB gp3 encrypted root volume
- **Monitoring**: Detailed CloudWatch monitoring enabled
- **User Data**: Minimal (CloudWatch agent only if enabled); registration via SSM Automation

### Security Groups

**AWS best practice**: Apply the principle of least privilege to network access ([SEC05-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_create_layers.html)).

- **Ingress**: None — publishers only initiate outbound connections, giving them zero inbound attack surface
- **Egress**: All outbound traffic allowed (0.0.0.0/0, all ports and protocols)
  - Egress is unrestricted because publishers must reach Netskope NewEdge, DNS, package repositories, and internal applications — destinations that vary per deployment

### VPC Endpoints

**AWS best practice**: Use VPC endpoints for AWS service traffic to keep it on the AWS private network and avoid NAT Gateway data processing charges ([SEC05-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_inspection.html)).

- Three Interface VPC Endpoints: `ssm`, `ssmmessages`, `ec2messages`
- SSM agent traffic stays within the AWS network, never traversing the NAT Gateway or public internet
- Enables Session Manager access to instances in private subnets without SSH or bastion hosts

### Netskope Provider

The Netskope Terraform provider creates publisher records and generates one-time registration tokens used during the SSM Automation registration step. It does not manage any AWS infrastructure.

- `netskope_npa_publisher`: Creates publisher records in the Netskope tenant
- `netskope_npa_publisher_token`: Generates one-time registration tokens
- Authentication: API key (set via environment variable or tfvars)

### Terraform State Backend (Optional)

**AWS best practice**: Encrypt state at rest with customer-managed KMS keys and use locking to prevent concurrent modifications ([SEC08-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_encrypt.html)).

- **S3 Bucket**: Encrypted state file storage with versioning
- **DynamoDB Table**: State locking (PAY_PER_REQUEST) for concurrent access protection
- **KMS Key**: Customer-managed encryption key
- See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for details

### CloudWatch (Optional)

- **Agent**: Memory and disk metrics (when `enable_cloudwatch_monitoring = true`)
- **SSM Parameter**: Stores CloudWatch agent configuration
- **Namespace**: `NPA/Publisher` for custom metrics

## Network Architecture

### Traffic Flows

#### 1. Publisher to Netskope NewEdge
```
NPA Publisher → Security Group (egress) → NAT Gateway →
Internet Gateway → Internet → Netskope NewEdge Data Centers
```
- **Port**: HTTPS (443)
- **Purpose**: Publisher registration, management plane, tunnel establishment

#### 2. Publisher to Internal Applications
```
NPA Publisher → Security Group (egress) →
VPC Internal / Peered VPCs / On-Premises (via VPN/Direct Connect)
```
- **Ports**: Application-specific
- **Destination**: RFC1918 private IP ranges
- **Purpose**: Proxying user traffic to internal applications via Netskope tunnels

#### 3. AWS Service Traffic (via VPC Endpoints)
```
NPA Publisher → VPC Endpoint (Interface) →
AWS Systems Manager Service Endpoints
```
- **Port**: HTTPS (443)
- **Purpose**: SSM agent communication, Session Manager access, publisher registration via SSM Automation
- VPC endpoints keep this traffic on the AWS private network, avoiding NAT Gateway data processing costs and removing a dependency on outbound internet for management operations

#### 4. Terraform Operator to AWS / Netskope APIs
```
Terraform Operator → AWS APIs (create/manage resources)
                   → Netskope APIs (create publishers, generate tokens)
```
- **Port**: HTTPS (443)
- **Source**: Operator workstation or CI/CD pipeline

### Network Segmentation

**AWS best practice**: Separate data, management, and control plane traffic using VPC constructs ([SEC05-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_create_layers.html)).

| Plane | Traffic | AWS Mechanism |
|---|---|---|
| **Data Plane** | Publisher ↔ Netskope NewEdge, internal apps | Private subnets → NAT Gateway → Internet / VPC peering |
| **Management Plane** | Operator ↔ Publisher (shell access, diagnostics) | Systems Manager Session Manager via VPC endpoints — no SSH, no bastion |
| **Control Plane** | Terraform ↔ AWS APIs, Netskope APIs | External (operator workstation / CI/CD) over HTTPS |

**Security Zones:**
- **Public Zone**: NAT Gateways only (no compute resources)
- **Private Zone**: NPA Publishers (compute resources)
- **External**: Terraform operator, Netskope NewEdge

## Security Architecture

This architecture implements defense in depth aligned to the [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html). Each layer references specific Security Pillar best practices.

### Layer 1: Network Security (SEC05)

> *SEC05-BP01: Create network layers* — SEC05-BP02: *Control traffic flow within network layers*

**VPC-Level Controls:**
- Private subnet placement for all compute resources
- No public IP addresses assigned to publishers
- Internet Gateway only accessible via NAT Gateways

**Security Group Configuration:**
```yaml
Ingress Rules: NONE
  - Publishers never accept inbound connections
  - Zero attack surface from internet

Egress Rules:
  1. All traffic → 0.0.0.0/0
     Purpose: Outbound connectivity for Netskope NewEdge, DNS,
              package repositories, and internal applications
```

**VPC Endpoints:**
- SSM traffic stays on the AWS private network (`ssm`, `ssmmessages`, `ec2messages`)
- Eliminates the need for public internet access for management operations

### Layer 2: Identity and Access Management (SEC02, SEC03)

> *SEC02-BP02: Use temporary credentials* — *SEC03-BP01: Define access requirements* — *SEC03-BP07: Analyze cross-account access*

**Three-role separation** ensures least privilege:

| Role | Assumed By | Purpose |
|---|---|---|
| **EC2 Instance Role** | `ec2.amazonaws.com` | SSM agent communication, CloudWatch agent (conditional). No access to registration tokens or infrastructure control plane. |
| **SSM Automation Role** | `ssm.amazonaws.com` | Server-side token resolution — reads registration tokens from SSM Parameter Store and runs registration on publisher instances. Token never leaves AWS. |
| **Terraform Operator** | Human / CI/CD | Manages all resources; additionally requires `ssm:StartAutomationExecution`, `ssm:GetAutomationExecution`, and `iam:PassRole` for the automation workflow. |

**Design rationale:**
- The EC2 instance role has no access to registration tokens — this is handled entirely by the SSM Automation role server-side, so tokens never transit the instance metadata service or operator workstation
- The SSM Automation role trust policy is limited to `ssm.amazonaws.com` and its `SendCommand` scope is restricted to publisher instances and `AWS-RunShellScript`
- See [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md) for minimum operator policy and [DEVOPS-NOTES.md](DEVOPS-NOTES.md#iam-configuration) for full permission enumerations

### Layer 3: Data Protection at Rest (SEC08)

> *SEC08-BP01: Implement secure key management* — *SEC08-BP02: Enforce encryption at rest*

**Terraform State Security:**
- **At rest**: KMS encryption with customer-managed key
- **Access control**: IAM policies on S3 bucket and KMS key
- **Versioning**: S3 versioning for state recovery
- **Locking**: DynamoDB prevents concurrent modifications

**What's in State:**
- Netskope API key (provider configuration)
- Publisher registration tokens (single-use)
- EC2 instance metadata, IAM configurations

See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for comprehensive state security guidance.

### Layer 4: Data Protection in Transit (SEC09)

> *SEC09-BP01: Implement secure key and certificate management* — *SEC09-BP02: Enforce encryption in transit*

- All AWS API calls: TLS 1.2+ (AWS SDK enforced)
- Netskope communication: TLS 1.3 (Netskope enforced)
- State transfers: HTTPS to S3
- EBS root volumes: Encrypted (gp3)
- SSM Parameter Store: SecureString for registration tokens

### Layer 5: Access Control (SEC02, SEC06)

> *SEC06-BP02: Reduce attack surface* — *SEC02-BP06: Employ user lifecycle management*

**Management Access:**
- **No SSH Required**: Systems Manager Session Manager for shell access
- **No Bastion Hosts**: Direct SSM connection from AWS Console or CLI
- **IMDSv2 Enforced**: Session tokens required for metadata access (SSRF protection)

**API Access:**
- **Netskope API**: Token-based authentication (set via environment variable)
- **AWS API**: IAM-based authentication (SigV4)

### Layer 6: Code Quality and Pre-commit (SEC01)

> *SEC01-BP06: Automate testing and validation of security controls*

**Automated Security Scanning:**
- **tfsec**: Terraform-specific security scanner
- **Checkov**: Compliance and misconfiguration scanner
- **gitleaks**: Scans for hardcoded secrets and credentials
- **detect-aws-credentials**: Prevents committing AWS credentials
- **detect-private-key**: Prevents committing private keys

**Code Quality:**
- **terraform fmt**: Consistent formatting
- **terraform validate**: Syntax validation
- **TFLint**: Linting and best practice enforcement
- **terraform-docs**: Auto-generated documentation

See [DEVOPS-NOTES.md](DEVOPS-NOTES.md) for pre-commit hook details.

## High Availability Design

### Multi-AZ Architecture

#### Availability Zone Distribution

**Active-Active Design:**
- Publishers distributed across AZs using `for_each` with modulo:
  ```hcl
  subnet_id = local.private_subnet_ids[each.value.index % length(local.private_subnet_ids)]
  ```
- Each instance handles traffic independently
- No active-passive failover required

**Zone-Isolated Failure Domains:**
- AZ1 failure: AZ2 continues serving traffic
- AZ2 failure: AZ1 continues serving traffic
- Independent NAT Gateways per AZ

#### Failure Scenarios and Recovery

**Scenario 1: Single Instance Failure**
- **Impact**: Reduced capacity (remaining instances continue serving)
- **Recovery**: `terraform apply -replace='aws_instance.publisher["name"]'`
- **Automatic**: Remaining instances continue without intervention

**Scenario 2: Availability Zone Failure**
- **Impact**: Instances in affected AZ unavailable
- **Recovery**: Healthy AZ continues serving all traffic automatically
- **Manual**: None required (wait for AZ recovery)

**Scenario 3: NAT Gateway Failure**
- **Impact**: Single AZ loses outbound internet
- **Recovery**: AWS restores NAT Gateway (99.99% SLA)

**Scenario 4: Region-Wide Failure**
- **Impact**: Entire deployment unavailable
- **Recovery**: Deploy in different region using same Terraform configuration

### Capacity and Scalability

**Scaling Publishers:**
```hcl
# Change publisher_count in terraform.tfvars
publisher_count = 4  # Scale from 2 to 4

# Apply the change
terraform apply
```

**Vertical Scaling:**
```hcl
# Change instance type
publisher_instance_type = "t3.xlarge"
```

| Instance Type | vCPU | Memory | Approximate Capacity |
|---|---|---|---|
| t3.medium | 2 | 4 GB | ~1,000 concurrent users |
| t3.large | 2 | 8 GB | ~2,000 concurrent users |
| t3.xlarge | 4 | 16 GB | ~4,000 concurrent users |
| t3.2xlarge | 8 | 32 GB | ~8,000 concurrent users |
| m5.large | 2 | 8 GB | ~2,000 concurrent users |
| m5.xlarge | 4 | 16 GB | ~4,000 concurrent users |
| m5.2xlarge | 8 | 32 GB | ~8,000 concurrent users |

### RPO and RTO

**Recovery Point Objective (RPO):**
- **Data Loss**: None (stateless publishers)
- **Configuration**: Stored in Git (version controlled .tf files)
- **Netskope State**: Maintained by Netskope cloud
- **Terraform State**: S3 versioning provides point-in-time recovery

**Recovery Time Objective (RTO):**
- **Single Instance**: Minutes (`terraform apply -replace`)
- **Availability Zone**: 0 seconds (automatic failover)
- **Entire Stack**: ~5-8 minutes (`terraform apply` from scratch)

## Additional Resources

- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) — Terraform state guide
- [QUICKSTART.md](QUICKSTART.md) — Quick deployment guide
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — Detailed deployment instructions
- [DEVOPS-NOTES.md](DEVOPS-NOTES.md) — Technical deep-dive
- [OPERATIONS.md](OPERATIONS.md) — Day-2 operational procedures
