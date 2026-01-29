# Basic Example

This example deploys a minimal NPA Publisher configuration with:
- New VPC with public and private subnets
- 2 NPA Publisher instances across availability zones
- NAT Gateways for outbound internet access
- Security groups with Netskope-required egress rules

## Usage

```bash
# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars

# Set sensitive values via environment variables
export TF_VAR_netskope_api_key="your-api-key"

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

## Requirements

- AWS credentials configured
- Netskope API key with publisher management permissions
- EC2 key pair created in target region

## Inputs

| Name | Description | Required |
|------|-------------|----------|
| netskope_server_url | Netskope API URL | Yes |
| netskope_api_key | Netskope API key | Yes |
| publisher_key_name | EC2 key pair name | Yes |
| publisher_name | Publisher name prefix | No |
| aws_region | AWS region | No |

## Outputs

| Name | Description |
|------|-------------|
| publisher_instance_ids | EC2 instance IDs |
| publisher_private_ips | Private IP addresses |
| publisher_names | Netskope publisher names |
| vpc_id | Created VPC ID |
| nat_gateway_public_ips | NAT Gateway IPs for whitelisting |
