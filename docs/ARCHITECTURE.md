# Architecture Overview

Comprehensive architecture documentation for the Netskope Private Access (NPA) Publisher deployment on AWS using Terraform.

## Table of Contents

- [Architecture Diagram](#architecture-diagram)
- [Component Overview](#component-overview)
- [Network Architecture](#network-architecture)
- [Security Architecture](#security-architecture)
- [High Availability Design](#high-availability-design)
- [AWS Well-Architected Alignment](#aws-well-architected-alignment)
- [Deployment Flow](#deployment-flow)
- [Resource Dependencies](#resource-dependencies)

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

### Key Differences from CloudFormation Architecture

| Aspect | CloudFormation | Terraform |
|---|---|---|
| **Publisher Registration** | Lambda + SSM Run Command | Netskope Terraform provider + user data script |
| **Secrets Management** | AWS Secrets Manager | Terraform state (encrypted with KMS) |
| **Token Delivery** | SSM encrypted channel | EC2 user data (base64 encoded) |
| **Orchestration** | CloudFormation engine | Terraform CLI (operator workstation or CI/CD) |
| **State Storage** | CloudFormation service (managed) | S3 + DynamoDB (self-managed) |
| **VPC Endpoints** | SSM endpoints (required for Lambda→SSM) | SSM endpoints (ssm, ssmmessages, ec2messages) |

## Component Overview

### Core Infrastructure Components

#### 1. VPC (Virtual Private Cloud)
- **Purpose**: Isolated network environment for NPA Publishers
- **CIDR**: 10.0.0.0/16 (default, configurable)
- **DNS**: Enabled for hostname resolution
- **Features**:
  - Multi-AZ design for high availability
  - Public and private subnet segregation
  - Redundant internet connectivity via NAT Gateways
- **Conditional**: Only created when `create_vpc = true`

#### 2. Subnets
- **Public Subnets** (10.0.1.0/24, 10.0.3.0/24):
  - Host NAT Gateways for outbound internet access
  - Route table: 0.0.0.0/0 → Internet Gateway

- **Private Subnets** (10.0.2.0/24, 10.0.4.0/24):
  - Host NPA Publisher EC2 instances
  - No direct internet access (egress via NAT Gateway)
  - Route table: 0.0.0.0/0 → NAT Gateway (in same AZ)

#### 3. Internet Gateway
- **Purpose**: Provides internet connectivity for the VPC
- **Used by**: NAT Gateways for outbound traffic

#### 4. NAT Gateways (2 instances)
- **Purpose**: Enable outbound internet access from private subnets
- **Deployment**: One per availability zone for redundancy
- **Benefits**:
  - Zone-isolated failure domains
  - Managed service (automatic scaling, patching)
  - Static Elastic IP for consistent egress IP

#### 5. EC2 Instances (NPA Publishers)
- **Type**: t3.large (default, configurable)
- **AMI**: Netskope Private Access Publisher (AWS Marketplace)
- **Deployment**: Distributed across AZs using `for_each` with modulo distribution
- **Networking**: Private subnet placement (no public IP)
- **IAM**: Instance profile with Systems Manager permissions
- **IMDS**: v2 required (session tokens for SSRF protection)
- **Storage**: 30 GB gp3 encrypted root volume
- **Monitoring**: Detailed CloudWatch monitoring enabled
- **User Data**: Registration script with Netskope token

#### 6. Security Groups
- **Ingress**: None — publishers only initiate outbound connections
- **Egress**:
  - VPC internal traffic (all protocols)
  - RFC1918 private ranges (peered VPCs, on-premises)
  - Netskope NewEdge IPs on port 443
  - HTTPS (443) to 0.0.0.0/0 (registration and updates)
  - DNS (UDP 53) to 0.0.0.0/0

#### 7. Netskope Terraform Provider
- **Purpose**: Creates and manages publisher records in Netskope tenant
- **Resources**:
  - `netskope_npa_publisher`: Publisher registration in Netskope
  - `netskope_npa_publisher_token`: One-time registration tokens
- **Authentication**: API key (set via environment variable or tfvars)

#### 8. Terraform State Backend (Optional)
- **S3 Bucket**: Encrypted state file storage with versioning
- **DynamoDB Table**: State locking for concurrent access protection
- **KMS Key**: Customer-managed encryption key for state
- **See**: [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for details

#### 9. CloudWatch (Optional)
- **Agent**: Memory and disk metrics (when `enable_cloudwatch_monitoring = true`)
- **SSM Parameter**: Stores CloudWatch agent configuration
- **Namespace**: `NPA/Publisher` for custom metrics

## Network Architecture

### Traffic Flows

#### 1. Publisher to Netskope NewEdge
```
NPA Publisher → Security Group (egress rules) → NAT Gateway →
Internet Gateway → Internet → Netskope NewEdge Data Centers
```
- **Port**: HTTPS (443)
- **Destination**: Netskope NewEdge IP ranges
- **Purpose**: Publisher registration, management, tunnel establishment

#### 2. Publisher to Internal Applications
```
NPA Publisher → Security Group (egress rules) →
VPC Internal / Peered VPCs / On-Premises (via VPN/Direct Connect)
```
- **Ports**: Application-specific
- **Destination**: RFC1918 private IP ranges
- **Purpose**: Proxying user traffic to internal applications

#### 3. Systems Manager Communication
```
NPA Publisher → VPC Endpoint (Interface) →
AWS Systems Manager Service Endpoints
```
- **Port**: HTTPS (443)
- **Purpose**: SSM agent communication, Session Manager access
- **Note**: SSM traffic uses Interface VPC endpoints (`ssm`, `ssmmessages`, `ec2messages`), keeping traffic within the AWS network without routing through the NAT Gateway.

#### 4. Terraform Operator to AWS / Netskope APIs
```
Terraform Operator → AWS APIs (create/manage resources)
                   → Netskope APIs (create publishers, generate tokens)
```
- **Port**: HTTPS (443)
- **Source**: Operator workstation or CI/CD pipeline
- **Purpose**: Infrastructure provisioning and management

### Network Segmentation

#### Isolation Strategy
1. **Data Plane Isolation**: Publishers in private subnets with no direct internet access
2. **Management Plane Access**: Via Systems Manager Session Manager (no SSH/bastion required)
3. **Control Plane**: Terraform operator runs from external location (workstation/CI/CD)

#### Security Zones
- **Public Zone**: NAT Gateways only (no compute resources)
- **Private Zone**: NPA Publishers (compute resources)
- **External**: Terraform operator, Netskope NewEdge

## Security Architecture

### Defense in Depth — Multi-Layer Security

#### Layer 1: Network Security

**VPC-Level Controls:**
- Private subnet placement for all compute resources
- No public IP addresses assigned to publishers
- Internet Gateway only accessible via NAT Gateways

**Security Group Configuration:**
```yaml
Ingress Rules: NONE
  - Publishers never accept inbound connections
  - Zero attack surface from internet

Egress Rules (Restrictive):
  1. All traffic → VPC CIDR
     Purpose: Internal application connectivity

  2. All traffic → RFC1918 ranges
     Purpose: Peered VPCs and on-premises networks

  3. HTTPS (443) → Netskope NewEdge IPs (5 CIDR blocks)
     Purpose: Publisher management and tunneling

  4. HTTPS (443) → 0.0.0.0/0
     Purpose: Registration and updates (pending IP restriction)

  5. DNS (UDP 53) → 0.0.0.0/0
     Purpose: Hostname resolution
```

#### Layer 2: IAM Least Privilege

**EC2 Instance Role:**
```yaml
Permissions:
  - AmazonSSMManagedInstanceCore          # SSM agent communication
  - CloudWatchAgentServerPolicy           # CloudWatch agent (conditional)
  - ssm:GetParameter (custom policy)      # CloudWatch config (conditional)

Restrictions:
  - No EC2 control plane permissions
  - No access to secrets services
  - No PassRole permissions
  - Cannot create/modify/delete infrastructure
```

**Terraform Operator:**
- Requires permissions to manage all resources in the configuration
- See [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md) for minimum policy

#### Layer 3: State Encryption

**Terraform State Security:**
- **At rest**: KMS encryption with customer-managed key
- **In transit**: HTTPS enforced via S3 bucket policy
- **Access control**: IAM policies on S3 bucket and KMS key
- **Versioning**: S3 versioning for state recovery
- **Locking**: DynamoDB prevents concurrent modifications

**What's in State:**
- Netskope API key (provider configuration)
- Publisher registration tokens (single-use)
- EC2 instance metadata, IAM configurations

> **Comparison with CloudFormation**: The CF version uses AWS Secrets Manager to store the API token and delivers registration tokens via encrypted SSM channels. In this Terraform version, the API key is in the provider configuration (and thus in state), and registration tokens are embedded in EC2 user data. The S3+KMS backend provides encryption at rest, but operators should understand this difference.

See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for comprehensive state security guidance.

#### Layer 4: Data Encryption

**Encryption in Transit:**
- All AWS API calls: TLS 1.2+ (AWS SDK enforced)
- Netskope communication: TLS 1.3 (Netskope enforced)
- State transfers: HTTPS to S3

**Encryption at Rest:**
- EBS root volumes: Encrypted (gp3)
- Terraform state: KMS-encrypted in S3
- CloudWatch agent config: SSM Parameter Store

#### Layer 5: Access Control

**Management Access:**
- **No SSH Required**: Systems Manager Session Manager for shell access
- **No Bastion Hosts**: Direct SSM connection from AWS Console or CLI
- **IMDSv2 Enforced**: Session tokens required for metadata access

**API Access:**
- **Netskope API**: Token-based authentication (set via environment variable)
- **AWS API**: IAM-based authentication (SigV4)

#### Layer 6: Code Quality and Pre-commit

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

### Security Best Practices Implemented

#### OWASP Top 10 for Infrastructure

1. **A01: Broken Access Control**
   - IAM least privilege enforced
   - No public access to resources
   - Security group ingress blocked

2. **A02: Cryptographic Failures**
   - State encrypted with KMS
   - TLS enforced for all communication
   - EBS volumes encrypted

3. **A07: Identification and Authentication Failures**
   - IAM role-based authentication
   - No hardcoded credentials (pre-commit hooks enforce this)
   - Token-based API authentication

4. **A09: Security Logging and Monitoring Failures**
   - CloudWatch monitoring available
   - SSM session logging
   - CloudTrail for API audit (recommended)

#### CIS AWS Foundations Benchmark

- **4.1**: No unrestricted ingress on port 22
- **4.2**: No unrestricted ingress on port 3389
- **2.1**: CloudWatch monitoring available
- **5.1**: VPC flow logs available (user-enabled)

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

## AWS Well-Architected Alignment

### 1. Reliability
- Multi-AZ deployment
- Managed services (NAT Gateway)
- Infrastructure as Code (repeatable deployments)
- `for_each` prevents cascading state changes

### 2. Security
- Defense in depth (6 layers)
- IAM least privilege
- Encrypted state and volumes
- Pre-commit security scanning
- No public IP addresses

### 3. Performance Efficiency
- Right-sized instances (configurable)
- Zone-local NAT Gateways
- gp3 EBS volumes (latest generation)

### 4. Cost Optimization
- No Lambda function costs
- No Secrets Manager costs
- PAY_PER_REQUEST DynamoDB for state locking
- Configurable instance types and count

### 5. Operational Excellence
- Infrastructure as Code (Terraform)
- Pre-commit hooks for quality gates
- Automated documentation generation
- Terratest for infrastructure testing
- Terraform plan as drift detection

## Deployment Flow

### Terraform Apply Sequence

```
1. Provider Initialization
   ├─ AWS provider configured (region, profile, default_tags)
   └─ Netskope provider configured (server_url, api_key)

2. Data Source Queries
   ├─ aws_availability_zones.available (query AZs)
   └─ aws_ami.netskope_publisher (find latest AMI)

3. VPC Resources (if create_vpc = true)
   ├─ aws_vpc.this
   ├─ aws_internet_gateway.this
   ├─ aws_subnet.public (2)
   ├─ aws_subnet.private (2)
   ├─ aws_eip.nat (2)
   ├─ aws_nat_gateway.this (2)
   ├─ aws_route_table.public + aws_route_table.private (2)
   ├─ aws_route_table_association (4)
   └─ aws_vpc_endpoint (3: ssm, ssmmessages, ec2messages)

4. Security Resources
   └─ aws_security_group.publisher

5. IAM Resources
   ├─ aws_iam_role.publisher
   ├─ aws_iam_instance_profile.publisher
   └─ aws_iam_role_policy_attachment (SSM, CloudWatch)

6. Netskope Resources
   ├─ netskope_npa_publisher.this (for_each: create publishers)
   └─ netskope_npa_publisher_token.this (for_each: generate tokens)

7. SSM Resources (if enable_cloudwatch_monitoring = true)
   └─ aws_ssm_parameter.cloudwatch_config

8. EC2 Instances
   └─ aws_instance.publisher (for_each: launch with user data)
       ├─ User data registers publisher with Netskope token
       └─ Optional: CloudWatch agent installation

Total Deployment Time: ~5-8 minutes
```

### Terraform Destroy Sequence

```
1. EC2 Instances terminated
2. Netskope publishers and tokens deleted (via provider)
3. SSM parameters deleted (if created)
4. IAM resources deleted
5. Security group deleted
6. VPC resources deleted (if created)
   ├─ VPC endpoints removed
   ├─ NAT Gateways released (EIPs freed)
   ├─ Route tables and associations removed
   ├─ Subnets deleted
   ├─ Internet Gateway detached and deleted
   └─ VPC deleted

Total Destruction Time: ~3-5 minutes
```

## Resource Dependencies

### Implicit Dependency Graph

Terraform automatically determines resource creation order based on references:

```
aws_vpc.this
  └─► aws_internet_gateway.this
  └─► aws_subnet.public
  │     └─► aws_eip.nat
  │     └─► aws_nat_gateway.this
  │           └─► aws_route_table.private
  └─► aws_subnet.private
  └─► aws_security_group.publisher

aws_iam_role.publisher
  └─► aws_iam_instance_profile.publisher
  └─► aws_iam_role_policy_attachment

netskope_npa_publisher.this
  └─► netskope_npa_publisher_token.this

aws_security_group.publisher ─┐
aws_iam_instance_profile.publisher ─┤
local.private_subnet_ids ─┤
netskope_npa_publisher_token.this ─┤
                                    └─► aws_instance.publisher
```

### External Dependencies

1. **Netskope Cloud**: Publisher management API must be reachable during `terraform apply`
2. **AWS Marketplace**: NPA Publisher AMI must be subscribed
3. **AWS Services**: EC2, VPC, IAM, SSM must be available in the target region
4. **Internet Connectivity**: Required for Netskope communication from publishers

## Additional Resources

- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) — Terraform state guide
- [QUICKSTART.md](QUICKSTART.md) — Quick deployment guide
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — Detailed deployment instructions
- [DEVOPS-NOTES.md](DEVOPS-NOTES.md) — Technical deep-dive
- [OPERATIONS.md](OPERATIONS.md) — Day-2 operational procedures
