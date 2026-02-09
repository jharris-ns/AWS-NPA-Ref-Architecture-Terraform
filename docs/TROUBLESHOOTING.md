# Troubleshooting Guide

Common issues and solutions for NPA Publisher Terraform deployments.

## Table of Contents

- [Terraform Deployment Issues](#terraform-deployment-issues)
- [Netskope Provider Issues](#netskope-provider-issues)
- [EC2 Instance Issues](#ec2-instance-issues)
- [Network Connectivity Issues](#network-connectivity-issues)
- [State Issues](#state-issues)
- [Diagnostic Commands](#diagnostic-commands)

## Terraform Deployment Issues

### Issue: terraform init Fails

**Symptom:** `Error: Failed to query available provider packages`

**Causes and solutions:**

1. **No internet access:**
   ```bash
   # Verify connectivity
   curl -I https://registry.terraform.io
   ```

2. **Provider not found:**
   ```bash
   # Verify provider source in terraform/versions.tf
   terraform {
     required_providers {
       netskope = {
         source  = "netskope/netskope"
         version = ">= 0.2.0"
       }
     }
   }
   ```

3. **Lock file conflict:**
   ```bash
   # Re-initialize with upgraded providers
   terraform init -upgrade
   ```

### Issue: terraform plan Shows Errors

**Symptom:** `Error: Invalid value for variable`

**Solution:** Check variable values against validation rules in `terraform/variables.tf`:

```bash
# Common validation errors:
# publisher_name must start with a letter: ^[a-zA-Z][a-zA-Z0-9-]*$
# publisher_count must be 1-10
# publisher_instance_type must be in allowed list
# environment must be: Production, Staging, Development, Test
```

**Symptom:** `Error: No valid credential sources found`

**Solution:** Configure AWS credentials:
```bash
# Check current credentials
aws sts get-caller-identity

# Set credentials
export AWS_PROFILE=my-profile
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

### Issue: terraform apply Fails Partway Through

**Symptom:** Some resources created, then error

**Solution:** Fix the error and re-run `terraform apply`. Terraform is idempotent — it will skip already-created resources and continue from where it stopped.

Common apply errors:

| Error | Cause | Solution |
|---|---|---|
| `Insufficient IAM permissions` | Missing permissions | See [IAM_PERMISSIONS.md](IAM_PERMISSIONS.md) |
| `AMI not found` | Wrong AMI ID or region | Check AMI subscription and region |
| `Key pair not found` | Key pair doesn't exist | Create key pair in target region |
| `VPC CIDR conflict` | CIDR overlaps existing VPC | Change `vpc_cidr` value |
| `Quota exceeded` | EC2/EIP/NAT limit reached | Request quota increase |

### Issue: terraform apply Hangs

**Symptom:** Apply appears stuck on a resource

**Causes:**
- **NAT Gateway**: Creation takes 2-3 minutes (normal)
- **EC2 Instance**: Launch takes 30-60 seconds (normal)
- **SSM polling**: `null_resource.publisher_registration` polls SSM until the instance is online (up to 10 minutes)
- **Netskope API timeout**: Provider waiting for API response

**Solution:** Wait for the operation to complete or timeout. SSM polling can take several minutes as it waits for the instance to boot and the SSM agent to connect. If stuck for more than 15 minutes, press Ctrl+C and investigate:

```bash
# Check if resources were partially created
terraform state list

# Check AWS for the resource
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*publisher*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

### Issue: terraform destroy Fails

**Symptom:** Resources cannot be deleted

**Common causes:**

1. **DependencyViolation** (security group in use):
   ```bash
   # Find what's using the security group
   aws ec2 describe-network-interfaces \
     --filters "Name=group-id,Values=sg-xxxxx" \
     --query 'NetworkInterfaces[*].[NetworkInterfaceId,Description]'
   ```

2. **NAT Gateway still deleting** — wait and retry

3. **Netskope API error** — publisher may already be deleted:
   ```bash
   # Remove from state if already deleted externally
   terraform state rm 'netskope_npa_publisher.this["my-publisher"]'
   terraform destroy  # Retry
   ```

## Netskope Provider Issues

### Issue: Authentication Failed

**Symptom:** `Error: Authentication failed` or `401 Unauthorized`

**Solutions:**

1. **Verify API key:**
   ```bash
   # Check the environment variable is set
   echo $TF_VAR_netskope_api_key | head -c 10
   # Should show first 10 characters

   # Test API directly
   curl -H "Netskope-Api-Token: $TF_VAR_netskope_api_key" \
     "$TF_VAR_netskope_server_url/infrastructure/publishers"
   ```

2. **Check server URL format:**
   ```bash
   # Correct format (include /api/v2):
   export TF_VAR_netskope_server_url="https://mytenant.goskope.com/api/v2"

   # Wrong formats:
   # https://mytenant.goskope.com        (missing /api/v2)
   # https://mytenant.goskope.com/api/v2/ (trailing slash may cause issues)
   ```

3. **Check token scopes** in Netskope UI:
   - Settings → Tools → REST API v2
   - Verify token has **Infrastructure Management** scope

### Issue: Publisher Creation Failed

**Symptom:** `Error: Failed to create publisher`

**Solutions:**

1. **Duplicate name:** Publisher names must be unique within a tenant
   ```bash
   # Check existing publishers
   curl -H "Netskope-Api-Token: $TF_VAR_netskope_api_key" \
     "$TF_VAR_netskope_server_url/infrastructure/publishers" | jq '.data.publishers[].publisher_name'
   ```

2. **API rate limiting:** Wait and retry
   ```bash
   terraform apply  # Retry
   ```

3. **Tenant issues:** Check Netskope service status

### Issue: Token Generation Failed

**Symptom:** `Error: Failed to generate registration token`

**Solution:** The publisher must exist before generating a token. Check that the publisher was created:

```bash
terraform state show 'netskope_npa_publisher.this["my-publisher"]'
```

If the publisher exists but token generation fails, it may be a transient API issue. Retry:
```bash
terraform apply
```

## EC2 Instance Issues

### Issue: Instance Not Running

**Symptom:** Instance state is `stopped`, `terminated`, or `pending`

**Diagnose:**
```bash
INSTANCE_ID=$(terraform output -json publisher_instance_ids | jq -r '.[0]')

aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[State.Name,StateReason.Message]' \
  --output text
```

**Common causes:**
- **InsufficientInstanceCapacity**: Try a different instance type or AZ
- **InvalidAMI**: AMI not available in region or subscription expired
- **InstanceLimitExceeded**: Request EC2 quota increase

### Issue: SSM Registration Failed

**Symptom:** `terraform apply` fails during `null_resource.publisher_registration` or publisher is not connected in Netskope

**Check Terraform output first** — registration errors are displayed in the `terraform apply` output, including the SSM command status and any error messages.

**Diagnose via SSM Session Manager:**
```bash
aws ssm start-session --target "$INSTANCE_ID"

# Check publisher service status
systemctl status npa_publisher_wizard || systemctl status npa_publisher

# Check docker logs (publisher runs in a container)
sudo docker logs $(sudo docker ps -q) 2>&1 | tail -20
```

**Check SSM command history:**
```bash
# List recent commands for the instance
aws ssm list-command-invocations \
  --instance-id "$INSTANCE_ID" \
  --query 'CommandInvocations[*].[CommandId,Status,RequestedDateTime]' \
  --output table
```

**Common causes:**
- **Instance not SSM-managed**: SSM agent not running or no network connectivity. Check VPC endpoints and NAT Gateway
- **Invalid registration token**: Token may have been consumed by a previous attempt (tokens are single-use)
- **Network issue**: Instance cannot reach Netskope endpoints
- **SSM polling timeout**: Instance took too long to come online (max 10 minutes)

**Recovery:**
```bash
# Re-run registration
terraform apply -replace='null_resource.publisher_registration["my-publisher"]'

# If token was consumed, replace everything
terraform apply \
  -replace='netskope_npa_publisher.this["my-publisher"]' \
  -replace='netskope_npa_publisher_token.this["my-publisher"]' \
  -replace='aws_instance.publisher["my-publisher"]'
```

### Issue: Instance Not Appearing in SSM

**Symptom:** `aws ssm start-session` fails with "target is not connected"

**Diagnose:**
```bash
# Check instance is running
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name'

# Check SSM agent status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].[PingStatus,LastPingDateTime]'
```

**Common causes:**

1. **IAM instance profile missing or wrong:**
   ```bash
   aws ec2 describe-instances \
     --instance-ids "$INSTANCE_ID" \
     --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
   # Should show the publisher instance profile
   ```

2. **Security group blocks outbound HTTPS:**
   ```bash
   SG_ID=$(terraform output -raw security_group_id)
   aws ec2 describe-security-groups \
     --group-ids "$SG_ID" \
     --query 'SecurityGroups[0].IpPermissionsEgress[?ToPort==`443`]'
   ```

3. **No route to internet (NAT Gateway issue):**
   ```bash
   # Check NAT Gateway status
   aws ec2 describe-nat-gateways \
     --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
     --query 'NatGateways[*].[NatGatewayId,State]' \
     --output table
   ```

4. **SSM agent not running on instance** — connect via EC2 Serial Console or replace the instance

## Network Connectivity Issues

### Issue: Publisher Not Connecting to Netskope NewEdge

**Diagnose from the instance (via SSM):**
```bash
aws ssm start-session --target "$INSTANCE_ID"

# Test connectivity to Netskope
curl -I https://mytenant.goskope.com
ping -c 3 8.36.116.1

# Test DNS
nslookup mytenant.goskope.com

# Check outbound connectivity
curl -I https://www.google.com
```

**Check security group egress rules:**
```bash
SG_ID=$(terraform output -raw security_group_id)
aws ec2 describe-security-groups \
  --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissionsEgress' \
  --output json
```

Required egress:
- All outbound traffic to 0.0.0.0/0 (the default security group configuration allows all outbound)

### Issue: NAT Gateway Not Working

**Diagnose:**
```bash
# Check NAT Gateway status
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'NatGateways[*].[NatGatewayId,State,SubnetId]' \
  --output table

# Check route table
SUBNET_ID=$(terraform output -json private_subnet_ids | jq -r '.[0]')
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]'
```

**NAT Gateway states:**
- `available`: Working correctly
- `pending`: Still creating (wait)
- `failed`: Creation failed (check EIP allocation)
- `deleting`: Being removed

### Issue: DNS Resolution Failing

**Diagnose from the instance:**
```bash
# Check DNS settings
cat /etc/resolv.conf

# Test DNS resolution
nslookup mytenant.goskope.com
dig mytenant.goskope.com
```

**Check VPC DNS settings:**
```bash
VPC_ID=$(terraform output -raw vpc_id)
aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsSupport
aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames
```

Both should return `"Value": true`.

## State Issues

### Issue: State Lock Stuck

**Symptom:** `Error: Error acquiring the state lock`

**Diagnose:**
```bash
# View current lock info
aws dynamodb get-item \
  --table-name npa-publisher-terraform-lock \
  --key '{"LockID":{"S":"npa-publisher-terraform-state-ACCOUNT_ID/npa-publishers/terraform.tfstate"}}'
```

**Solution:**

First, verify no other Terraform process is running. Then:
```bash
# Get the lock ID from the error message
terraform force-unlock LOCK_ID
```

> **Warning**: Only force-unlock when you are certain no other process is running.

### Issue: State Out of Sync

**Symptom:** `terraform plan` shows changes for resources that haven't actually changed

**Solution:**

```bash
# Refresh state from actual infrastructure
terraform apply -refresh-only
```

This updates state to match the current state of resources in AWS/Netskope without making any changes to infrastructure.

### Issue: State Corruption

**Symptom:** `Error: Error loading state` or unexpected resource entries

**Solution with S3 versioning:**

```bash
# List recent state versions
aws s3api list-object-versions \
  --bucket npa-publisher-terraform-state-ACCOUNT_ID \
  --prefix npa-publishers/terraform.tfstate \
  --query 'Versions[0:5].[VersionId,LastModified]' \
  --output table

# Download a known-good version
aws s3api get-object \
  --bucket npa-publisher-terraform-state-ACCOUNT_ID \
  --key npa-publishers/terraform.tfstate \
  --version-id "GOOD_VERSION_ID" \
  recovered.json

# Push the recovered state
terraform state push recovered.json
```

See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for comprehensive recovery procedures.

### Issue: Lost State

**Symptom:** State file missing or empty, but infrastructure exists

**Solution:** Rebuild state by importing each resource:

```bash
terraform import 'aws_vpc.this[0]' vpc-xxxxx
terraform import 'aws_security_group.publisher' sg-xxxxx
terraform import 'aws_instance.publisher["my-publisher"]' i-xxxxx
# ... import remaining resources

terraform plan
# Fix any configuration differences
```

## Diagnostic Commands

### Terraform Diagnostics

```bash
# Check Terraform version and providers
terraform version

# List managed resources
terraform state list

# Show specific resource details
terraform state show 'aws_instance.publisher["my-publisher"]'

# Validate configuration
terraform validate

# Plan with detailed output
terraform plan -detailed-exitcode
# 0=no changes, 1=error, 2=changes detected

# Enable debug logging
TF_LOG=DEBUG terraform plan 2>terraform-debug.log
```

### AWS CLI Diagnostics

```bash
# Current identity
aws sts get-caller-identity

# Instance details
INSTANCE_ID=$(terraform output -json publisher_instance_ids | jq -r '.[0]')
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --output json

# Instance console output (boot log)
aws ec2 get-console-output \
  --instance-id "$INSTANCE_ID" \
  --output text

# Security group rules
SG_ID=$(terraform output -raw security_group_id)
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$SG_ID" \
  --output table

# NAT Gateway status
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --output table

# SSM instance info
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID"
```

### Netskope API Diagnostics

```bash
# Test API connectivity
curl -v -H "Netskope-Api-Token: $TF_VAR_netskope_api_key" \
  "$TF_VAR_netskope_server_url/infrastructure/publishers"

# List all publishers
curl -s -H "Netskope-Api-Token: $TF_VAR_netskope_api_key" \
  "$TF_VAR_netskope_server_url/infrastructure/publishers" \
  | jq '.data.publishers[] | {publisher_name, publisher_id, status}'
```

## Getting Help

If you're still experiencing issues:

1. **Collect diagnostics** using the commands above
2. **Check AWS Service Health Dashboard** for regional outages
3. **Check Netskope System Status** for service issues
4. **Review Terraform debug logs** (`TF_LOG=DEBUG terraform plan`)
5. **File an issue** on the GitHub repository with:
   - Terraform version (`terraform version`)
   - Error messages (full output)
   - Deployment mode (new VPC / existing VPC, local / remote state)
   - Relevant diagnostic command outputs

## Additional Resources

- [OPERATIONS.md](OPERATIONS.md) — Operational procedures
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) — State management and recovery
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — Deployment instructions
- [Netskope REST API v2](https://docs.netskope.com/en/rest-api-v2-overview-312207.html)
- [Terraform Debugging](https://developer.hashicorp.com/terraform/internals/debugging)
- [AWS Systems Manager Troubleshooting](https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting-remote-commands.html)
