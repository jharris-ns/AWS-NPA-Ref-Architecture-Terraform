<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_netskope"></a> [netskope](#requirement\_netskope) | >= 0.2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.28.0 |
| <a name="provider_netskope"></a> [netskope](#provider\_netskope) | 0.3.2 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cloudwatch_config_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cloudwatch_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.ssm_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.cloudwatch_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.ec2messages](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.ssmmessages](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [netskope_npa_publisher.this](https://registry.terraform.io/providers/netskopeoss/netskope/latest/docs/resources/npa_publisher) | resource |
| [netskope_npa_publisher_token.this](https://registry.terraform.io/providers/netskopeoss/netskope/latest/docs/resources/npa_publisher_token) | resource |
| [aws_ami.netskope_publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_iam_policy_document.cloudwatch_config_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ec2_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones for subnets (auto-select if empty) | `list(string)` | `[]` | no |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS CLI profile name (optional) | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for deployment | `string` | `"us-east-1"` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | Cost center for billing allocation | `string` | `"IT-Operations"` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create new VPC (true) or use existing (false) | `bool` | `true` | no |
| <a name="input_enable_cloudwatch_monitoring"></a> [enable\_cloudwatch\_monitoring](#input\_enable\_cloudwatch\_monitoring) | Install CloudWatch agent for memory/disk metrics (~$2.40/month per instance) | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment type | `string` | `"Production"` | no |
| <a name="input_existing_private_subnet_ids"></a> [existing\_private\_subnet\_ids](#input\_existing\_private\_subnet\_ids) | Existing private subnet IDs (used when create\_vpc=false) | `list(string)` | `[]` | no |
| <a name="input_existing_vpc_id"></a> [existing\_vpc\_id](#input\_existing\_vpc\_id) | Existing VPC ID (used when create\_vpc=false) | `string` | `""` | no |
| <a name="input_netskope_api_key"></a> [netskope\_api\_key](#input\_netskope\_api\_key) | Netskope API key. Recommend setting via NETSKOPE\_API\_KEY env var | `string` | n/a | yes |
| <a name="input_netskope_server_url"></a> [netskope\_server\_url](#input\_netskope\_server\_url) | Netskope API server URL (e.g., https://tenant.goskope.com/api/v2) | `string` | n/a | yes |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | CIDR blocks for private subnets (Publishers) | `list(string)` | <pre>[<br/>  "10.0.2.0/24",<br/>  "10.0.4.0/24"<br/>]</pre> | no |
| <a name="input_project"></a> [project](#input\_project) | Project name for resource tracking | `string` | `"NPA-Publisher"` | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | CIDR blocks for public subnets (NAT Gateways) | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.3.0/24"<br/>]</pre> | no |
| <a name="input_publisher_ami_id"></a> [publisher\_ami\_id](#input\_publisher\_ami\_id) | AMI ID for NPA publisher (auto-detect if empty) | `string` | `""` | no |
| <a name="input_publisher_count"></a> [publisher\_count](#input\_publisher\_count) | Number of publisher instances to deploy | `number` | `2` | no |
| <a name="input_publisher_instance_type"></a> [publisher\_instance\_type](#input\_publisher\_instance\_type) | EC2 instance type for publishers | `string` | `"t3.large"` | no |
| <a name="input_publisher_key_name"></a> [publisher\_key\_name](#input\_publisher\_key\_name) | EC2 key pair name for SSH access | `string` | n/a | yes |
| <a name="input_publisher_name"></a> [publisher\_name](#input\_publisher\_name) | Base name for NPA publishers | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for VPC (used when create\_vpc=true or for security group rules) | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | NAT Gateway IDs (if created by this module) |
| <a name="output_nat_gateway_public_ips"></a> [nat\_gateway\_public\_ips](#output\_nat\_gateway\_public\_ips) | NAT Gateway public IPs (if created by this module) |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs (if created by this module) |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs (if created by this module) |
| <a name="output_publisher_ids"></a> [publisher\_ids](#output\_publisher\_ids) | Netskope Publisher IDs |
| <a name="output_publisher_instance_ids"></a> [publisher\_instance\_ids](#output\_publisher\_instance\_ids) | EC2 instance IDs of the NPA Publishers |
| <a name="output_publisher_names"></a> [publisher\_names](#output\_publisher\_names) | Names of the NPA Publishers in Netskope |
| <a name="output_publisher_private_ips"></a> [publisher\_private\_ips](#output\_publisher\_private\_ips) | Private IP addresses of the NPA Publishers |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID for the NPA Publishers |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID (if created by this module) |
<!-- END_TF_DOCS --><!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_netskope"></a> [netskope](#requirement\_netskope) | >= 0.3.3 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.31.0 |
| <a name="provider_netskope"></a> [netskope](#provider\_netskope) | 0.3.4 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ssm_automation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cloudwatch_config_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ssm_automation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cloudwatch_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.ssm_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_document.publisher_registration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [aws_ssm_parameter.cloudwatch_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.publisher_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.ec2messages](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.ssmmessages](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [netskope_npa_publisher.this](https://registry.terraform.io/providers/netskopeoss/netskope/latest/docs/resources/npa_publisher) | resource |
| [netskope_npa_publisher_token.this](https://registry.terraform.io/providers/netskopeoss/netskope/latest/docs/resources/npa_publisher_token) | resource |
| [null_resource.publisher_registration](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_ami.netskope_publisher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.cloudwatch_config_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ec2_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ssm_automation_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ssm_automation_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones for subnets (auto-select if empty) | `list(string)` | `[]` | no |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS CLI profile name (optional) | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for deployment | `string` | `"us-east-1"` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create new VPC (true) or use existing (false) | `bool` | `true` | no |
| <a name="input_enable_cloudwatch_monitoring"></a> [enable\_cloudwatch\_monitoring](#input\_enable\_cloudwatch\_monitoring) | Install CloudWatch agent for memory/disk metrics (~$2.40/month per instance) | `bool` | `false` | no |
| <a name="input_existing_private_subnet_ids"></a> [existing\_private\_subnet\_ids](#input\_existing\_private\_subnet\_ids) | Existing private subnet IDs (used when create\_vpc=false) | `list(string)` | `[]` | no |
| <a name="input_existing_vpc_id"></a> [existing\_vpc\_id](#input\_existing\_vpc\_id) | Existing VPC ID (used when create\_vpc=false) | `string` | `""` | no |
| <a name="input_netskope_api_key"></a> [netskope\_api\_key](#input\_netskope\_api\_key) | Netskope API key. Recommend setting via NETSKOPE\_API\_KEY env var | `string` | n/a | yes |
| <a name="input_netskope_server_url"></a> [netskope\_server\_url](#input\_netskope\_server\_url) | Netskope API server URL (e.g., https://tenant.goskope.com/api/v2) | `string` | n/a | yes |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | CIDR blocks for private subnets (Publishers) | `list(string)` | <pre>[<br/>  "10.0.2.0/24",<br/>  "10.0.4.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | CIDR blocks for public subnets (NAT Gateways) | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.3.0/24"<br/>]</pre> | no |
| <a name="input_publisher_ami_id"></a> [publisher\_ami\_id](#input\_publisher\_ami\_id) | AMI ID for NPA publisher (auto-detect if empty) | `string` | `""` | no |
| <a name="input_publisher_count"></a> [publisher\_count](#input\_publisher\_count) | Number of publisher instances to deploy | `number` | `2` | no |
| <a name="input_publisher_instance_type"></a> [publisher\_instance\_type](#input\_publisher\_instance\_type) | EC2 instance type for publishers | `string` | `"t3.large"` | no |
| <a name="input_publisher_key_name"></a> [publisher\_key\_name](#input\_publisher\_key\_name) | EC2 key pair name for SSH access | `string` | n/a | yes |
| <a name="input_publisher_name"></a> [publisher\_name](#input\_publisher\_name) | Base name for NPA publishers | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags applied to all AWS resources via provider default\_tags | `map(string)` | <pre>{<br/>  "ManagedBy": "Terraform"<br/>}</pre> | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for VPC (used when create\_vpc=true or for security group rules) | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | NAT Gateway IDs (if created by this module) |
| <a name="output_nat_gateway_public_ips"></a> [nat\_gateway\_public\_ips](#output\_nat\_gateway\_public\_ips) | NAT Gateway public IPs (if created by this module) |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs (if created by this module) |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs (if created by this module) |
| <a name="output_publisher_ids"></a> [publisher\_ids](#output\_publisher\_ids) | Netskope Publisher IDs |
| <a name="output_publisher_instance_ids"></a> [publisher\_instance\_ids](#output\_publisher\_instance\_ids) | EC2 instance IDs of the NPA Publishers |
| <a name="output_publisher_names"></a> [publisher\_names](#output\_publisher\_names) | Names of the NPA Publishers in Netskope |
| <a name="output_publisher_private_ips"></a> [publisher\_private\_ips](#output\_publisher\_private\_ips) | Private IP addresses of the NPA Publishers |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID for the NPA Publishers |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID (if created by this module) |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
