# ==============================================================================
# VPC Resources (Conditional)
# ==============================================================================
# This file creates the networking infrastructure:
#   - VPC (Virtual Private Cloud) - isolated network in AWS
#   - Internet Gateway - allows internet access for public subnets
#   - Public Subnets - for NAT Gateways (have internet access)
#   - Private Subnets - for Publishers (no direct internet access)
#   - NAT Gateways - allow private subnets to reach internet (outbound only)
#   - Route Tables - define how traffic flows between subnets and internet
#
# All resources use "count" to make them conditional:
#   count = var.create_vpc ? 1 : 0
#   - If create_vpc is true: create 1 resource
#   - If create_vpc is false: create 0 resources (skip entirely)
#
# When using count, resources become lists and must be referenced with [0]:
#   aws_vpc.this[0].id  (not aws_vpc.this.id)
# ==============================================================================

# ------------------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------------------
# A VPC is your isolated network within AWS. All resources (EC2, RDS, etc.)
# are launched into a VPC. Key settings:
#   - cidr_block: The IP address range for the entire VPC
#   - enable_dns_hostnames: Allows EC2 instances to get DNS names
#   - enable_dns_support: Enables DNS resolution within the VPC
# ------------------------------------------------------------------------------
resource "aws_vpc" "this" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags help identify resources; Name tag appears in AWS Console
  tags = { Name = "${var.publisher_name}-vpc" }
}

# ------------------------------------------------------------------------------
# Internet Gateway
# ------------------------------------------------------------------------------
# An Internet Gateway allows resources in public subnets to communicate with
# the internet. It's attached to the VPC and referenced in route tables.
#
# Without an IGW, no resources in the VPC can reach the internet.
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id # Reference the VPC created above

  tags = { Name = "${var.publisher_name}-igw" }
}

# ------------------------------------------------------------------------------
# Public Subnets (for NAT Gateways)
# ------------------------------------------------------------------------------
# Subnets divide the VPC's IP range into smaller segments.
# Public subnets have a route to the Internet Gateway.
#
# count = var.create_vpc ? length(var.public_subnet_cidrs) : 0
#   - This creates one subnet PER CIDR in the list
#   - If create_vpc is false, creates 0 subnets
#
# count.index: The current iteration number (0, 1, 2, ...)
#   - Used to get the corresponding CIDR from the list
#   - Used to distribute subnets across AZs
#
# map_public_ip_on_launch: Instances get public IPs automatically
# ------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index % length(local.azs)] # Distributes across AZs
  map_public_ip_on_launch = true                                       # Public subnets get public IPs

  tags = { Name = "${var.publisher_name}-public-${count.index + 1}" }
}

# ------------------------------------------------------------------------------
# Public Route Table
# ------------------------------------------------------------------------------
# Route tables define where network traffic is directed.
# This route table sends all non-local traffic (0.0.0.0/0) to the Internet Gateway.
#
# 0.0.0.0/0 means "all IP addresses" - it's the default route for internet access.
# Local VPC traffic is automatically routed (implicit route).
# ------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"                     # All traffic...
    gateway_id = aws_internet_gateway.this[0].id # ...goes to the Internet Gateway
  }

  tags = { Name = "${var.publisher_name}-public-rt" }
}

# ------------------------------------------------------------------------------
# Public Route Table Associations
# ------------------------------------------------------------------------------
# Associates each public subnet with the public route table.
# Without this, subnets use the VPC's default route table (no internet access).
# ------------------------------------------------------------------------------
resource "aws_route_table_association" "public" {
  count = var.create_vpc ? length(aws_subnet.public) : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# ------------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# ------------------------------------------------------------------------------
# Elastic IPs are static public IP addresses that persist even if resources
# are stopped/started. NAT Gateways require an Elastic IP.
#
# domain = "vpc": Allocates the EIP for use in a VPC (required for NAT Gateway)
#
# depends_on: Explicitly declares that this resource depends on another.
# Terraform usually figures out dependencies automatically, but sometimes
# you need to be explicit (like here - EIP needs IGW to exist first).
# ------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0

  domain = "vpc"

  tags = { Name = "${var.publisher_name}-nat-eip-${count.index + 1}" }

  depends_on = [aws_internet_gateway.this] # Must exist before creating EIP
}

# ------------------------------------------------------------------------------
# NAT Gateways (one per AZ for redundancy)
# ------------------------------------------------------------------------------
# NAT (Network Address Translation) Gateways allow resources in private
# subnets to access the internet (outbound only - no inbound connections).
#
# Traffic flow: Private Instance -> NAT Gateway -> Internet Gateway -> Internet
#
# We create one NAT Gateway per AZ for high availability:
#   - If one AZ has issues, the other NAT Gateway still works
#   - This costs more ($32/month each) but provides redundancy
# ------------------------------------------------------------------------------
resource "aws_nat_gateway" "this" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0

  allocation_id = aws_eip.nat[count.index].id       # The Elastic IP to use
  subnet_id     = aws_subnet.public[count.index].id # Must be in a PUBLIC subnet

  tags = { Name = "${var.publisher_name}-nat-${count.index + 1}" }

  depends_on = [aws_internet_gateway.this]
}

# ------------------------------------------------------------------------------
# Private Subnets (for Publishers)
# ------------------------------------------------------------------------------
# Private subnets do NOT have direct internet access.
# Resources here reach the internet through NAT Gateways.
#
# This is more secure for backend services like NPA Publishers:
#   - No public IP = can't be directly accessed from internet
#   - Outbound access only through NAT Gateway
# ------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = var.create_vpc ? length(var.private_subnet_cidrs) : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]
  # Note: NO map_public_ip_on_launch - instances stay private

  tags = { Name = "${var.publisher_name}-private-${count.index + 1}" }
}

# ------------------------------------------------------------------------------
# Private Route Tables
# ------------------------------------------------------------------------------
# Each private subnet gets its own route table pointing to its AZ's NAT Gateway.
# This ensures traffic uses the NAT Gateway in the same AZ for:
#   - Lower latency
#   - Resilience if one AZ fails
# ------------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count = var.create_vpc ? length(var.private_subnet_cidrs) : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block     = "0.0.0.0/0"                          # All traffic...
    nat_gateway_id = aws_nat_gateway.this[count.index].id # ...goes to NAT Gateway
  }

  tags = { Name = "${var.publisher_name}-private-rt-${count.index + 1}" }
}

# ------------------------------------------------------------------------------
# Private Route Table Associations
# ------------------------------------------------------------------------------
resource "aws_route_table_association" "private" {
  count = var.create_vpc ? length(aws_subnet.private) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ------------------------------------------------------------------------------
# VPC Endpoints for Systems Manager
# ------------------------------------------------------------------------------
# Interface VPC endpoints allow private subnets to reach AWS Systems Manager
# without routing through the NAT Gateway. This provides:
#   - Lower latency for SSM operations
#   - Traffic stays within the AWS network (no internet traversal)
#   - Continued SSM access even if NAT Gateway is unavailable
#
# Three endpoints are required for full SSM Session Manager functionality:
#   - ssm: SSM API calls
#   - ssmmessages: Session Manager data channel
#   - ec2messages: SSM agent message delivery
# ------------------------------------------------------------------------------

resource "aws_security_group" "ssm_endpoint" {
  count = var.create_vpc ? 1 : 0

  name        = "${var.publisher_name}-ssm-endpoint-sg"
  description = "Security group for SSM VPC endpoints"
  vpc_id      = aws_vpc.this[0].id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.publisher_name}-ssm-endpoint-sg" }
}

resource "aws_vpc_endpoint" "ssm" {
  count = var.create_vpc ? 1 : 0

  vpc_id              = aws_vpc.this[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ssm_endpoint[0].id]

  tags = { Name = "${var.publisher_name}-ssm-endpoint" }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.create_vpc ? 1 : 0

  vpc_id              = aws_vpc.this[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ssm_endpoint[0].id]

  tags = { Name = "${var.publisher_name}-ssmmessages-endpoint" }
}

resource "aws_vpc_endpoint" "ec2messages" {
  count = var.create_vpc ? 1 : 0

  vpc_id              = aws_vpc.this[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ssm_endpoint[0].id]

  tags = { Name = "${var.publisher_name}-ec2messages-endpoint" }
}
