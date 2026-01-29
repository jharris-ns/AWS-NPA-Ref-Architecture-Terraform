# ==============================================================================
# Local Values
# ==============================================================================
# Locals are computed values used within the module. They differ from variables
# in that they're calculated internally rather than provided by the user.
#
# Use locals to:
#   - Simplify complex expressions used multiple times
#   - Create conditional logic
#   - Reduce repetition
#   - Transform input variables into usable forms
#
# Reference with: local.<name> (e.g., local.vpc_id)
# ==============================================================================

locals {
  # --------------------------------------------------------------------------
  # AMI Selection
  # --------------------------------------------------------------------------
  # Use user-provided AMI ID if specified, otherwise use auto-detected AMI.
  # The [0] index is needed because the data source uses count (making it a list).
  # --------------------------------------------------------------------------
  publisher_ami_id = var.publisher_ami_id != "" ? var.publisher_ami_id : data.aws_ami.netskope_publisher[0].id

  # --------------------------------------------------------------------------
  # Availability Zone Selection
  # --------------------------------------------------------------------------
  # Use user-specified AZs if provided, otherwise auto-select first 2 available.
  # slice(list, start, end) extracts elements from index start to end-1.
  # --------------------------------------------------------------------------
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  # --------------------------------------------------------------------------
  # VPC and Subnet Selection
  # --------------------------------------------------------------------------
  # Conditionally use created or existing VPC/subnets based on create_vpc flag.
  # The [0] index handles the count-based conditional resource creation.
  # The [*] splat expression extracts attributes from all list items.
  # --------------------------------------------------------------------------
  vpc_id             = var.create_vpc ? aws_vpc.this[0].id : var.existing_vpc_id
  private_subnet_ids = var.create_vpc ? aws_subnet.private[*].id : var.existing_private_subnet_ids

  # --------------------------------------------------------------------------
  # Publisher Name Map
  # --------------------------------------------------------------------------
  # Generates a map of publisher keys to metadata for use with for_each.
  # Using for_each (instead of count) prevents cascading state changes when
  # a publisher is removed from the middle of the set.
  #
  # Keys are human-readable publisher names, making state addresses clear:
  #   netskope_npa_publisher.this["my-pub"]
  #   netskope_npa_publisher.this["my-pub-2"]
  # --------------------------------------------------------------------------
  publishers = {
    for i in range(var.publisher_count) :
    (i == 0 ? var.publisher_name : "${var.publisher_name}-${i + 1}") => {
      index = i
      name  = i == 0 ? var.publisher_name : "${var.publisher_name}-${i + 1}"
    }
  }

}
