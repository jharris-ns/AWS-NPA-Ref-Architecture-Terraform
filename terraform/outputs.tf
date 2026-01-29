# ==============================================================================
# Outputs
# ==============================================================================
# Outputs expose values from your Terraform configuration.
# They're displayed after "terraform apply" and can be queried with
# "terraform output" or "terraform output <name>".
#
# Common uses:
#   - Display important information (IPs, URLs, IDs) after deployment
#   - Pass values to other Terraform configurations (modules, workspaces)
#   - Integrate with external tools and scripts
#
# Output attributes:
#   - description: Documents what the output represents
#   - value: The actual value to output
#   - sensitive: Hide value in logs (use for secrets)
#
# For count-based resources, [*] (splat) extracts attributes from all items.
# For for_each resources, values() converts the map to a list first:
#   values(aws_instance.publisher)[*].id = ["i-abc123", "i-def456"]
# ==============================================================================

# ------------------------------------------------------------------------------
# EC2 Instance Outputs
# ------------------------------------------------------------------------------
output "publisher_instance_ids" {
  description = "EC2 instance IDs of the NPA Publishers"
  value       = values(aws_instance.publisher)[*].id
  # Example: ["i-0abc123def456789", "i-0xyz987wvu654321"]
}

output "publisher_private_ips" {
  description = "Private IP addresses of the NPA Publishers"
  value       = values(aws_instance.publisher)[*].private_ip
  # Example: ["10.0.2.45", "10.0.4.67"]
  # Use these IPs to connect via SSM Session Manager or SSH (if in VPC)
}

# ------------------------------------------------------------------------------
# Netskope Publisher Outputs
# ------------------------------------------------------------------------------
output "publisher_names" {
  description = "Names of the NPA Publishers in Netskope"
  value       = values(netskope_npa_publisher.this)[*].publisher_name
  # Example: ["my-publisher", "my-publisher-2"]
  # These names appear in the Netskope admin console
}

output "publisher_ids" {
  description = "Netskope Publisher IDs"
  value       = values(netskope_npa_publisher.this)[*].publisher_id
  # These IDs are used when configuring private apps in Netskope
}

# ------------------------------------------------------------------------------
# Security Group Output
# ------------------------------------------------------------------------------
output "security_group_id" {
  description = "Security group ID for the NPA Publishers"
  value       = aws_security_group.publisher.id
  # Useful if you need to add this SG as a source in other security groups
}

# ------------------------------------------------------------------------------
# VPC Outputs (Conditional)
# ------------------------------------------------------------------------------
# These outputs only have values if var.create_vpc is true.
# If using an existing VPC, these will be null.
#
# The ternary operator returns null when create_vpc is false:
#   var.create_vpc ? <value> : null

output "vpc_id" {
  description = "VPC ID (if created by this module)"
  value       = var.create_vpc ? aws_vpc.this[0].id : null
}

output "private_subnet_ids" {
  description = "Private subnet IDs (if created by this module)"
  value       = var.create_vpc ? aws_subnet.private[*].id : null
}

output "public_subnet_ids" {
  description = "Public subnet IDs (if created by this module)"
  value       = var.create_vpc ? aws_subnet.public[*].id : null
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs (if created by this module)"
  value       = var.create_vpc ? aws_nat_gateway.this[*].id : null
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway public IPs (if created by this module)"
  value       = var.create_vpc ? aws_eip.nat[*].public_ip : null
  # These IPs are what external services see when publishers make outbound connections.
  # Useful for whitelisting in firewalls or security groups of target applications.
}
