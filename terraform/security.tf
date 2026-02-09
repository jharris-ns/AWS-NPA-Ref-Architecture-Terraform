# ==============================================================================
# Security Groups
# ==============================================================================
# Security Groups act as virtual firewalls for EC2 instances.
# They control inbound (ingress) and outbound (egress) traffic.
#
# Key concepts:
#   - Security groups are STATEFUL: if you allow outbound traffic, the
#     response is automatically allowed back in (and vice versa)
#   - Default behavior: all inbound DENIED, all outbound ALLOWED
#   - Rules are additive: you add ALLOW rules (there's no explicit DENY)
#   - Multiple security groups can be attached to one instance
#
# For NPA Publishers:
#   - No inbound rules needed (publishers initiate all connections)
#   - Outbound rules allow:
#     * Connections to Netskope cloud (for registration and tunnels)
#     * Connections to internal apps (that publishers proxy access to)
# ==============================================================================

resource "aws_security_group" "publisher" {
  name        = "${var.publisher_name}-sg"
  description = "Security group for Netskope NPA Publishers"
  vpc_id      = local.vpc_id # Use the VPC (created or existing)

  # ==========================================================================
  # INGRESS RULES (Inbound Traffic)
  # ==========================================================================
  # No ingress rules - publishers don't need inbound traffic
  # They establish outbound connections to Netskope and internal resources

  # ==========================================================================
  # EGRESS RULES (Outbound Traffic)
  # ==========================================================================
  # Egress rules define what outbound connections the publisher can make.
  #
  # Rule structure:
  #   - from_port/to_port: Port range (use 0/0 with protocol -1 for "all")
  #   - protocol: "tcp", "udp", "icmp", or "-1" for all
  #   - cidr_blocks: Destination IP ranges (list format)
  #   - description: Documents the rule's purpose (shown in AWS Console)
  # ==========================================================================

  # --------------------------------------------------------------------------
  # VPC Internal Traffic
  # --------------------------------------------------------------------------
  # Allows the publisher to communicate with any resource in the VPC.
  # This is essential for connecting to private applications.
  # --------------------------------------------------------------------------
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0    # All ports
    to_port     = 0    # All ports
    protocol    = "-1" # All protocols
    cidr_blocks = [var.vpc_cidr]
  }

  # --------------------------------------------------------------------------
  # RFC1918 Private IP Ranges
  # --------------------------------------------------------------------------
  # RFC1918 defines private IP address ranges that aren't routed on the internet:
  #   - 10.0.0.0/8     (Class A: 10.0.0.0 - 10.255.255.255)
  #   - 172.16.0.0/12  (Class B: 172.16.0.0 - 172.31.255.255)
  #   - 192.168.0.0/16 (Class C: 192.168.0.0 - 192.168.255.255)
  #
  # Publishers may need to connect to apps in peered VPCs or on-premises
  # networks using these ranges.
  # --------------------------------------------------------------------------
  egress {
    description = "RFC1918 Class A - Network segment discovery"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "RFC1918 Class B - Network segment discovery"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["172.16.0.0/12"]
  }

  egress {
    description = "RFC1918 Class C - Network segment discovery"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.0.0/16"]
  }

  # --------------------------------------------------------------------------
  # Internet Egress (All Traffic)
  # --------------------------------------------------------------------------
  # Publishers need outbound access for:
  #   - Netskope cloud registration and tunnel establishment
  #   - Netskope NewEdge data center connections
  #   - OS and Docker package updates
  #   - DNS resolution
  #
  # TODO: For production, consider restricting to specific ports/CIDRs.
  # --------------------------------------------------------------------------
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.publisher_name}-sg" }
}
