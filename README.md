# terraform-aws-langfuse-eks

Terraform module that deploys [Langfuse](https://langfuse.com) — the open-source LLM observability platform — on an existing Amazon EKS cluster.

[![CI](https://github.com/josemiguelalves/terraform-aws-langfuse-eks/actions/workflows/ci.yml/badge.svg)](https://github.com/josemiguelalves/terraform-aws-langfuse-eks/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Architecture

```
                        ┌─────────────────────────────────────────────────────────┐
                        │  Amazon EKS                                             │
Internet ──► Route 53   │                                                         │
               │        │  ┌──────────────── ALB (AWS LBC) ──────────────────┐   │
               │        │  │  /api/public  (no auth)  ─────► langfuse-web    │   │
               └──────► │  │  /            (Cognito*)  ─────► langfuse-web   │   │
                        │  └──────────────────────────────────────────────────┘   │
                        │                                                         │
                        │  Namespace: langfuse                                    │
                        │  ┌─────────────┐  ┌──────────┐  ┌──────────────────┐  │
                        │  │ langfuse-web│  │ worker   │  │  ClickHouse      │  │
                        │  │ (NextJS)    │  │          │  │  (analytics DB)  │  │
                        │  └─────────────┘  └──────────┘  └──────────────────┘  │
                        │  ┌─────────────┐  ┌──────────┐                         │
                        │  │ PostgreSQL  │  │  Redis   │                         │
                        │  │ (EFS PV)    │  │ (EFS PV) │                         │
                        │  └─────────────┘  └──────────┘                         │
                        │                                                         │
                        │  Karpenter NodePool (langfuse)                          │
                        │  taint: storageType=efs:NoSchedule                      │
                        └─────────────────────────────────────────────────────────┘
                                              │
                              ┌───────────────┴──────────────────┐
                              │  S3 bucket (events/exports/media) │
                              └───────────────────────────────────┘

  * Cognito SSO is optional (var.cognito_enabled)
```

---

## Features

- **One-command deploy** – Helm chart + all supporting AWS resources from a single `terraform apply`
- **Auto-generated secrets** – PostgreSQL, Redis, ClickHouse passwords; SALT; NEXTAUTH_SECRET; ENCRYPTION_KEY — all generated with `random_bytes` / `random_password`
- **Dedicated Karpenter NodePool** – nodes are tainted so only Langfuse pods land there; configurable AZs, instance families and resource limits
- **Dual ALB Ingress** – `/api/public` bypasses auth (SDK trace ingestion), root path applies Cognito SSO when enabled
- **Scoped IAM** – IRSA role with S3 permissions limited to the module-owned bucket
- **EKS Access Entries** – uses the modern `aws_eks_access_entry` resource, no `eksctl` dependency
- **S3 lifecycle tiering** – STANDARD_IA at 90 days, Glacier IR at 180 days
- **Optional Cognito SSO** – plug in an existing Cognito User Pool to front the web UI

---

## Prerequisites

The following must already exist in your AWS account before applying this module:

| Requirement | Notes |
|---|---|
| EKS cluster (>= 1.28) | With access entries auth mode enabled |
| [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) | Manages ALB ingress resources |
| [Karpenter](https://karpenter.sh) | Node auto-provisioning |
| [EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver) | EFS persistent volumes |
| EFS file system | Accessible from the EKS VPC |
| ACM certificate | Covers the `hosted_zone_name` domain |
| Route 53 hosted zone | Public zone for the `hosted_zone_name` domain |
| EBS `gp3` StorageClass | Named `gp3` (for ClickHouse dynamic provisioning) |

---

## Usage

### Minimal

```hcl
module "langfuse" {
  source  = "josemiguelalves/langfuse-eks/aws"
  version = "~> 0.1"

  aws_account_id  = "123456789012"
  aws_region      = "us-east-1"
  identifier      = "myapp-prod"
  environment     = "prod"

  eks_cluster_name                = "my-cluster"
  eks_openid_connect_provider_url = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  eks_openid_connect_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  node_instance_role_name         = "my-cluster-node-instance-role"

  main_private_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  main_public_subnet_ids  = ["subnet-ddd", "subnet-eee", "subnet-fff"]

  efs_file_system_id = "fs-0123456789abcdef0"
  storage_class_name = "efs"

  certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/EXAMPLE"
  hosted_zone_name = "example.com"
}
```

### With Cognito SSO

```hcl
module "langfuse" {
  source  = "josemiguelalves/langfuse-eks/aws"
  version = "~> 0.1"

  # ... required variables above ...

  cognito_enabled            = true
  cognito_user_pool_id       = "us-east-1_XXXXXXXXX"
  cognito_user_pool_arn      = "arn:aws:cognito-idp:us-east-1:123456789012:userpool/us-east-1_XXXXXXXXX"
  cognito_domain             = "my-app-auth"
  cognito_identity_providers = ["COGNITO"]
}
```

### Providers block (required in the calling module/stack)

```hcl
data "aws_eks_cluster"      "this" { name = var.eks_cluster_name }
data "aws_eks_cluster_auth" "this" { name = var.eks_cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}
```

> **Note** Provider configurations are not passed into child modules in Terraform. You must configure the `aws`, `kubernetes`, `helm` and `kubectl` providers in your root module.

---

## Examples

| Example | Description |
|---|---|
| [basic](examples/basic/) | Minimum required variables, no Cognito |
| [complete](examples/complete/) | All options: Cognito SSO, custom sizing, explicit S3 bucket name |

---

## Secret management

All credentials are generated once by Terraform and stored in:
- The Terraform state (encrypt your backend at rest)
- A Kubernetes Secret named `langfuse-credentials` in the `langfuse` namespace

To rotate a secret, taint the relevant `random_password` or `random_bytes` resource:

```bash
terraform taint 'random_password.postgresql'
terraform apply
```

---

## IAM permissions

The IRSA role attached to the `langfuse` Kubernetes service account has:

| Permission | Scope |
|---|---|
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` | Module S3 bucket only |
| `kms:GenerateDataKey`, `kms:Decrypt` | `*` (narrow to your CMK ARN if applicable) |

---

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
