# Basic Example

Deploys Langfuse on EKS with default settings and no Cognito SSO. All secrets are generated automatically.

## Prerequisites

- EKS cluster with Karpenter, AWS Load Balancer Controller and EFS CSI driver installed
- EFS file system accessible from the cluster
- ACM certificate and Route 53 hosted zone for TLS/DNS

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars  # fill in your values
terraform init
terraform apply
```

## terraform.tfvars.example

```hcl
aws_account_id                  = "123456789012"
aws_region                      = "us-east-1"
eks_cluster_name                = "my-cluster"
eks_openid_connect_provider_url = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
eks_openid_connect_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
node_instance_role_name         = "my-cluster-node-instance-role"
main_private_subnet_ids         = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
main_public_subnet_ids          = ["subnet-ddd", "subnet-eee", "subnet-fff"]
efs_file_system_id              = "fs-0123456789abcdef0"
certificate_arn                 = "arn:aws:acm:us-east-1:123456789012:certificate/EXAMPLE"
hosted_zone_name                = "example.com"
```
