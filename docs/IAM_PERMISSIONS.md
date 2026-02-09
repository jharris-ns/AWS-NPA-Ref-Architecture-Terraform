# IAM Permissions Guide

IAM permissions required to deploy and manage the NPA Publisher Terraform configuration.

## Table of Contents

- [Overview](#overview)
- [Terraform Operator Permissions](#terraform-operator-permissions)
- [Create a Dedicated Deployment Role](#create-a-dedicated-deployment-role)
- [CI/CD Pipeline Permissions](#cicd-pipeline-permissions)
- [Security Best Practices](#security-best-practices)
- [Cleanup](#cleanup)
- [Quick Reference](#quick-reference)

## Overview

The Terraform operator needs IAM permissions to create and manage NPA infrastructure. If using remote state with S3, the operator also needs access to the state backend resources (S3, DynamoDB, KMS).

## Terraform Operator Permissions

The minimum IAM policy for deploying the NPA Publisher infrastructure.

### Full Policy Document

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2Management",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeImages",
        "ec2:DescribeKeyPairs",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags",
        "ec2:ModifyInstanceAttribute",
        "ec2:DescribeInstanceAttribute"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VPCManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:DescribeVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:DescribeNatGateways",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:CreateVpcEndpoint",
        "ec2:DeleteVpcEndpoints",
        "ec2:DescribeVpcEndpoints",
        "ec2:ModifyVpcEndpoint"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecurityGroupManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:PassRole",
        "iam:TagRole",
        "iam:UntagRole"
      ],
      "Resource": [
        "arn:aws:iam::*:role/*publisher*",
        "arn:aws:iam::*:role/*Publisher*",
        "arn:aws:iam::*:instance-profile/*publisher*",
        "arn:aws:iam::*:instance-profile/*Publisher*"
      ]
    },
    {
      "Sid": "SSMManagement",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:DeleteParameter",
        "ssm:DescribeParameters",
        "ssm:AddTagsToResource",
        "ssm:RemoveTagsFromResource",
        "ssm:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMRunCommand",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMSessionManager",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:DescribeSessions",
        "ssm:DescribeInstanceInformation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchManagement",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagResource",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AvailabilityZoneDiscovery",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAvailabilityZones"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::*-terraform-state-*",
        "arn:aws:s3:::*-terraform-state-*/*"
      ]
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/*-terraform-lock"
    },
    {
      "Sid": "TerraformStateEncryption",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "kms:ViaService": "s3.*.amazonaws.com"
        }
      }
    }
  ]
}
```

### Permission Summary

| Service | Actions | Purpose |
|---|---|---|
| **EC2** | RunInstances, TerminateInstances, Describe* | Manage publisher instances |
| **VPC** | Create/Delete VPC, Subnets, NAT, IGW, Routes, VPC Endpoints | Network infrastructure |
| **Security Groups** | Create/Delete, Authorize/Revoke rules | Firewall management |
| **IAM** | Create/Delete roles, profiles, attach policies | Instance role management |
| **SSM** | PutParameter, GetParameter, SendCommand, StartSession | Token storage, publisher registration, shell access |
| **CloudWatch** | Log groups, alarms | Monitoring |
| **S3** | GetObject, PutObject | Terraform state (if remote) |
| **DynamoDB** | GetItem, PutItem, DeleteItem | State locking (if remote) |
| **KMS** | Encrypt, Decrypt, GenerateDataKey | State encryption (if remote) |

## Create a Dedicated Deployment Role

### Step 1: Save the Policy

Save the Terraform Operator policy from above as `npa-deploy-policy.json`.

### Step 2: Create the IAM Policy

```bash
aws iam create-policy \
  --policy-name NPAPublisherTerraformPolicy \
  --policy-document file://npa-deploy-policy.json \
  --description "Permissions for deploying NPA Publisher via Terraform"
```

Save the policy ARN from the output.

### Step 3: Create a Trust Policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)

cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${USER_ARN}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

### Step 4: Create and Configure the Role

```bash
# Create the role
aws iam create-role \
  --role-name NPAPublisherTerraformRole \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "Role for deploying NPA Publisher via Terraform"

# Attach the policy
aws iam attach-role-policy \
  --role-name NPAPublisherTerraformRole \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/NPAPublisherTerraformPolicy"

# Clean up
rm /tmp/trust-policy.json
```

### Step 5: Configure AWS Profile

Add to `~/.aws/config`:

```ini
[profile npa-deployer]
role_arn = arn:aws:iam::123456789012:role/NPAPublisherTerraformRole
source_profile = default
region = us-east-1
```

### Step 6: Use the Role

```bash
# Option A: AWS profile
export AWS_PROFILE=npa-deployer
terraform apply

# Option B: Terraform variable
terraform apply -var="aws_profile=npa-deployer"
```

## CI/CD Pipeline Permissions

### GitHub Actions with OIDC

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:*"
        }
      }
    }
  ]
}
```

### GitLab CI with OIDC

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.com:sub": "project_path:GROUP/PROJECT:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
```

### Pipeline Permissions

CI/CD pipelines need the same Terraform Operator permissions, plus:

```json
{
  "Sid": "TerraformPlanArtifacts",
  "Effect": "Allow",
  "Action": [
    "s3:PutObject",
    "s3:GetObject"
  ],
  "Resource": "arn:aws:s3:::your-ci-artifacts-bucket/*"
}
```

## Security Best Practices

### 1. Require MFA for Role Assumption

```json
{
  "Condition": {
    "Bool": {
      "aws:MultiFactorAuthPresent": "true"
    }
  }
}
```

Assume role with MFA:
```bash
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT:role/NPAPublisherTerraformRole \
  --role-session-name deploy \
  --serial-number arn:aws:iam::ACCOUNT:mfa/username \
  --token-code 123456
```

### 2. Limit Session Duration

```bash
aws iam update-role \
  --role-name NPAPublisherTerraformRole \
  --max-session-duration 3600  # 1 hour
```

### 3. Restrict Source IP

Add to trust policy conditions:
```json
{
  "IpAddress": {
    "aws:SourceIp": ["203.0.113.0/24"]
  }
}
```

### 4. Enable CloudTrail

Monitor who uses the deployment role:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=NPAPublisherTerraformRole \
  --max-items 20
```

### 5. Never Use Root Credentials

Always use IAM roles or users with scoped permissions. Never deploy infrastructure using the AWS account root user.

## Cleanup

Remove the deployment role and policy when no longer needed:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Detach policy from role
aws iam detach-role-policy \
  --role-name NPAPublisherTerraformRole \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/NPAPublisherTerraformPolicy"

# Delete role
aws iam delete-role --role-name NPAPublisherTerraformRole

# Delete policy
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/NPAPublisherTerraformPolicy"
```

## Quick Reference

```bash
# Check current identity
aws sts get-caller-identity

# Assume the deployment role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT:role/NPAPublisherTerraformRole \
  --role-session-name deploy

# List policies on the role
aws iam list-attached-role-policies --role-name NPAPublisherTerraformRole

# Test permissions (validate without deploying)
terraform plan

# Use named profile
export AWS_PROFILE=npa-deployer
terraform apply
```

## Additional Resources

- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) — State access permissions
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — Deployment instructions
- [AWS IAM Roles Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
