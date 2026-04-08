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

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.3.0 |
| aws | >= 5.61 |
| helm | >= 2.7 |
| kubectl | >= 2.0.0 |
| kubernetes | >= 2.10 |
| null | >= 3.0 |
| random | >= 3.0 |

## Providers

| Name | Version |
|---|---|
| aws | >= 5.61 |
| helm | >= 2.7 |
| kubectl (alekc/kubectl) | >= 2.0.0 |
| kubernetes | >= 2.10 |
| null | >= 3.0 |
| random | >= 3.0 |

## Resources

| Name | Type |
|---|---|
| `aws_cognito_user_pool_client.langfuse` | resource |
| `aws_efs_access_point.postgresql` | resource |
| `aws_efs_access_point.redis` | resource |
| `aws_eks_access_entry.langfuse` | resource |
| `aws_iam_policy.langfuse_s3` | resource |
| `aws_iam_role.langfuse` | resource |
| `aws_iam_role_policy_attachment.langfuse_s3` | resource |
| `aws_route53_record.langfuse` | resource |
| `aws_s3_bucket.langfuse` | resource |
| `aws_s3_bucket_lifecycle_configuration.langfuse` | resource |
| `aws_s3_bucket_public_access_block.langfuse` | resource |
| `aws_s3_bucket_versioning.langfuse` | resource |
| `helm_release.langfuse` | resource |
| `kubectl_manifest.langfuse_api_ingress` | resource |
| `kubectl_manifest.langfuse_cluster_role` | resource |
| `kubectl_manifest.langfuse_node_class` | resource |
| `kubectl_manifest.langfuse_node_pool` | resource |
| `kubectl_manifest.langfuse_web_ingress` | resource |
| `kubernetes_namespace_v1.langfuse` | resource |
| `kubernetes_persistent_volume.postgresql` | resource |
| `kubernetes_persistent_volume.redis` | resource |
| `kubernetes_secret.langfuse` | resource |
| `kubernetes_service_account_v1.langfuse` | resource |
| `null_resource.configure_kubectl` | resource |
| `random_bytes.encryption_key` | resource |
| `random_bytes.nextauth_secret` | resource |
| `random_bytes.salt` | resource |
| `random_password.clickhouse` | resource |
| `random_password.postgresql` | resource |
| `random_password.redis` | resource |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `aws_account_id` | AWS account ID where resources will be deployed. | `string` | n/a | yes |
| `aws_region` | AWS region where resources will be deployed. | `string` | n/a | yes |
| `certificate_arn` | ARN of the ACM certificate used by the ALB HTTPS listener. | `string` | n/a | yes |
| `efs_file_system_id` | ID of the existing EFS file system. | `string` | n/a | yes |
| `eks_cluster_name` | Name of the existing EKS cluster. | `string` | n/a | yes |
| `eks_openid_connect_provider_arn` | ARN of the OIDC provider for the EKS cluster. | `string` | n/a | yes |
| `eks_openid_connect_provider_url` | OIDC provider URL of the EKS cluster. | `string` | n/a | yes |
| `environment` | Deployment environment label (e.g. dev, staging, prod). | `string` | n/a | yes |
| `hosted_zone_name` | Route 53 hosted zone name (e.g. example.com). | `string` | n/a | yes |
| `identifier` | Unique identifier used to name AWS resources. | `string` | n/a | yes |
| `main_private_subnet_ids` | Private subnet IDs for EKS node placement. | `list(string)` | n/a | yes |
| `main_public_subnet_ids` | Public subnet IDs for the internet-facing ALB. | `list(string)` | n/a | yes |
| `node_instance_role_name` | IAM role name attached to EKS worker nodes (Karpenter EC2NodeClass). | `string` | n/a | yes |
| `storage_class_name` | Kubernetes StorageClass name backed by EFS CSI driver. | `string` | n/a | yes |
| `clickhouse_cpu` | CPU request for ClickHouse pods. | `string` | `"2"` | no |
| `clickhouse_memory` | Memory request/limit for ClickHouse pods. | `string` | `"6Gi"` | no |
| `clickhouse_replicas` | Number of ClickHouse replicas. | `number` | `1` | no |
| `cognito_domain` | Cognito hosted-UI domain prefix. | `string` | `null` | no |
| `cognito_enabled` | Enable Cognito SSO via the ALB authenticator. | `bool` | `false` | no |
| `cognito_extra_callback_urls` | Additional OAuth callback URLs. | `list(string)` | `[]` | no |
| `cognito_extra_logout_urls` | Additional logout redirect URLs. | `list(string)` | `[]` | no |
| `cognito_identity_providers` | Cognito identity providers (e.g. COGNITO, Google). | `list(string)` | `["COGNITO"]` | no |
| `cognito_user_pool_arn` | ARN of the existing Cognito User Pool. | `string` | `null` | no |
| `cognito_user_pool_id` | Existing Cognito User Pool ID. | `string` | `null` | no |
| `dns_record_name` | DNS record prefix in the hosted zone. | `string` | `"langfuse"` | no |
| `extra_helm_values` | Additional raw YAML values merged into the Langfuse Helm release. | `string` | `""` | no |
| `langfuse_chart_version` | Version of the Langfuse Helm chart. | `string` | `"1.5.22"` | no |
| `langfuse_cpu` | CPU request/limit for Langfuse web and worker pods. | `string` | `"1"` | no |
| `langfuse_memory` | Memory request/limit for Langfuse web and worker pods. | `string` | `"4Gi"` | no |
| `langfuse_web_replicas` | Number of Langfuse web pod replicas. | `number` | `1` | no |
| `langfuse_worker_replicas` | Number of Langfuse worker pod replicas. | `number` | `1` | no |
| `node_pool_availability_zones` | Availability zones for the Karpenter NodePool. | `list(string)` | `null` | no |
| `node_pool_cpu_limit` | Max CPU across all Langfuse nodes. | `number` | `50` | no |
| `node_pool_instance_categories` | EC2 instance categories for the NodePool. | `list(string)` | `["c","m","r"]` | no |
| `node_pool_memory_limit` | Max memory across all Langfuse nodes. | `string` | `"500Gi"` | no |
| `s3_bucket_name` | Name of the S3 bucket. Defaults to `<identifier>-langfuse`. | `string` | `null` | no |
| `tags` | Additional tags applied to all AWS resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `alb_dns_name` | DNS name of the Application Load Balancer. |
| `cognito_client_id` | Cognito App Client ID (null when cognito_enabled = false). |
| `helm_release_status` | Status of the Langfuse Helm release. |
| `iam_role_arn` | ARN of the IRSA role attached to the Langfuse service account. |
| `langfuse_url` | Public URL of the Langfuse web UI. |
| `namespace` | Kubernetes namespace where Langfuse is deployed. |
| `s3_bucket_arn` | ARN of the S3 bucket for blob storage. |
| `s3_bucket_name` | Name of the S3 bucket for blob storage. |

<!-- END_TF_DOCS -->

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
