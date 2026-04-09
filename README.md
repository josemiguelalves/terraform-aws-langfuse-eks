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
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.61 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.7 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 2.0.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.61 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.7 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 2.0.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10 |
| <a name="provider_null"></a> [null](#provider\_null) | >= 3.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cognito_user_pool_client.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_efs_access_point.postgresql](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_access_point.redis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_eks_access_entry.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_iam_policy.langfuse_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.langfuse_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_route53_record.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_public_access_block.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_versioning.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [helm_release.langfuse](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubectl_manifest.langfuse_api_ingress](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.langfuse_cluster_role](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.langfuse_node_class](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.langfuse_node_pool](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.langfuse_web_ingress](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.langfuse](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_persistent_volume.postgresql](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/persistent_volume) | resource |
| [kubernetes_persistent_volume.redis](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/persistent_volume) | resource |
| [kubernetes_secret.langfuse](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service_account_v1.langfuse](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account_v1) | resource |
| [null_resource.configure_kubectl](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_bytes.encryption_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/bytes) | resource |
| [random_bytes.nextauth_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/bytes) | resource |
| [random_bytes.salt](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/bytes) | resource |
| [random_password.clickhouse](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.postgresql](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.redis](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_iam_policy_document.langfuse_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.langfuse_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_lb.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/lb) | data source |
| [aws_route53_zone.langfuse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region where resources will be deployed (e.g. us-east-1). | `string` | n/a | yes |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ARN of the ACM certificate used by the ALB HTTPS listener. | `string` | n/a | yes |
| <a name="input_clickhouse_cpu"></a> [clickhouse\_cpu](#input\_clickhouse\_cpu) | CPU request for ClickHouse pods. | `string` | `"2"` | no |
| <a name="input_clickhouse_memory"></a> [clickhouse\_memory](#input\_clickhouse\_memory) | Memory request/limit for ClickHouse pods. | `string` | `"6Gi"` | no |
| <a name="input_clickhouse_replicas"></a> [clickhouse\_replicas](#input\_clickhouse\_replicas) | Number of ClickHouse replicas. | `number` | `1` | no |
| <a name="input_cognito_domain"></a> [cognito\_domain](#input\_cognito\_domain) | Cognito hosted-UI domain prefix (e.g. myapp-auth). The full domain is <cognito\_domain>.auth.<region>.amazoncognito.com. | `string` | `null` | no |
| <a name="input_cognito_enabled"></a> [cognito\_enabled](#input\_cognito\_enabled) | Set to true to front the Langfuse web UI with AWS Cognito SSO via the ALB authenticator. Requires cognito\_user\_pool\_id, cognito\_user\_pool\_arn and cognito\_domain. | `bool` | `false` | no |
| <a name="input_cognito_extra_callback_urls"></a> [cognito\_extra\_callback\_urls](#input\_cognito\_extra\_callback\_urls) | Additional OAuth callback URLs appended to the Cognito App Client (e.g. localhost for dev). | `list(string)` | `[]` | no |
| <a name="input_cognito_extra_logout_urls"></a> [cognito\_extra\_logout\_urls](#input\_cognito\_extra\_logout\_urls) | Additional logout redirect URLs appended to the Cognito App Client. | `list(string)` | `[]` | no |
| <a name="input_cognito_identity_providers"></a> [cognito\_identity\_providers](#input\_cognito\_identity\_providers) | List of Cognito identity providers to allow (e.g. ['COGNITO', 'Google', 'my-saml-idp']). | `list(string)` | <pre>[<br/>  "COGNITO"<br/>]</pre> | no |
| <a name="input_cognito_user_pool_arn"></a> [cognito\_user\_pool\_arn](#input\_cognito\_user\_pool\_arn) | ARN of the existing Cognito User Pool. | `string` | `null` | no |
| <a name="input_cognito_user_pool_id"></a> [cognito\_user\_pool\_id](#input\_cognito\_user\_pool\_id) | Existing Cognito User Pool ID. | `string` | `null` | no |
| <a name="input_dns_record_name"></a> [dns\_record\_name](#input\_dns\_record\_name) | DNS record prefix created in the hosted zone (e.g. langfuse). The full URL will be https://<dns\_record\_name>.<hosted\_zone\_name>. | `string` | `"langfuse"` | no |
| <a name="input_efs_file_system_id"></a> [efs\_file\_system\_id](#input\_efs\_file\_system\_id) | ID of the existing EFS file system used for PostgreSQL and Redis persistent volumes. | `string` | n/a | yes |
| <a name="input_eks_cluster_name"></a> [eks\_cluster\_name](#input\_eks\_cluster\_name) | Name of the existing EKS cluster. | `string` | n/a | yes |
| <a name="input_eks_openid_connect_provider_arn"></a> [eks\_openid\_connect\_provider\_arn](#input\_eks\_openid\_connect\_provider\_arn) | ARN of the OIDC provider for the EKS cluster. | `string` | n/a | yes |
| <a name="input_eks_openid_connect_provider_url"></a> [eks\_openid\_connect\_provider\_url](#input\_eks\_openid\_connect\_provider\_url) | OIDC provider URL of the EKS cluster (e.g. https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment label (e.g. dev, staging, prod). Used in resource tags. | `string` | n/a | yes |
| <a name="input_extra_helm_values"></a> [extra\_helm\_values](#input\_extra\_helm\_values) | Additional raw YAML values to merge into the Langfuse Helm release. Useful for customising sub-charts without forking the module. | `string` | `""` | no |
| <a name="input_hosted_zone_name"></a> [hosted\_zone\_name](#input\_hosted\_zone\_name) | Route 53 hosted zone name (e.g. example.com). | `string` | n/a | yes |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Unique identifier used to name AWS resources (e.g. myapp-prod). Must be lowercase alphanumeric with hyphens. | `string` | n/a | yes |
| <a name="input_langfuse_chart_version"></a> [langfuse\_chart\_version](#input\_langfuse\_chart\_version) | Version of the Langfuse Helm chart to deploy. See https://github.com/langfuse/langfuse-k8s/releases. | `string` | `"1.5.22"` | no |
| <a name="input_langfuse_cpu"></a> [langfuse\_cpu](#input\_langfuse\_cpu) | CPU request/limit for Langfuse web and worker pods. | `string` | `"1"` | no |
| <a name="input_langfuse_memory"></a> [langfuse\_memory](#input\_langfuse\_memory) | Memory request/limit for Langfuse web and worker pods. | `string` | `"4Gi"` | no |
| <a name="input_langfuse_web_replicas"></a> [langfuse\_web\_replicas](#input\_langfuse\_web\_replicas) | Number of Langfuse web pod replicas. | `number` | `1` | no |
| <a name="input_langfuse_worker_replicas"></a> [langfuse\_worker\_replicas](#input\_langfuse\_worker\_replicas) | Number of Langfuse worker pod replicas. | `number` | `1` | no |
| <a name="input_main_public_subnet_ids"></a> [main\_public\_subnet\_ids](#input\_main\_public\_subnet\_ids) | Public subnet IDs for the internet-facing ALB. | `list(string)` | n/a | yes |
| <a name="input_node_instance_role_name"></a> [node\_instance\_role\_name](#input\_node\_instance\_role\_name) | Name of the IAM role attached to EKS worker nodes. Required by Karpenter EC2NodeClass. | `string` | n/a | yes |
| <a name="input_node_pool_availability_zones"></a> [node\_pool\_availability\_zones](#input\_node\_pool\_availability\_zones) | Availability zones for the Langfuse Karpenter NodePool. Defaults to a, b, c zones of the target region. | `list(string)` | `null` | no |
| <a name="input_node_pool_cpu_limit"></a> [node\_pool\_cpu\_limit](#input\_node\_pool\_cpu\_limit) | Maximum CPU units allocatable across all Langfuse nodes. | `number` | `50` | no |
| <a name="input_node_pool_instance_categories"></a> [node\_pool\_instance\_categories](#input\_node\_pool\_instance\_categories) | EC2 instance categories (c = compute, m = general, r = memory) eligible for the Langfuse NodePool. | `list(string)` | <pre>[<br/>  "c",<br/>  "m",<br/>  "r"<br/>]</pre> | no |
| <a name="input_node_pool_memory_limit"></a> [node\_pool\_memory\_limit](#input\_node\_pool\_memory\_limit) | Maximum memory allocatable across all Langfuse nodes. | `string` | `"500Gi"` | no |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | Name of the S3 bucket for Langfuse blob storage. Defaults to '<identifier>-langfuse'. | `string` | `null` | no |
| <a name="input_storage_class_name"></a> [storage\_class\_name](#input\_storage\_class\_name) | Kubernetes StorageClass name backed by EFS CSI driver (e.g. efs). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to all AWS resources created by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the Application Load Balancer created by the AWS Load Balancer Controller. |
| <a name="output_cognito_client_id"></a> [cognito\_client\_id](#output\_cognito\_client\_id) | Cognito App Client ID. Only populated when cognito\_enabled = true. |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the Langfuse Helm release. |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the IAM role attached to the Langfuse Kubernetes service account (IRSA). |
| <a name="output_langfuse_url"></a> [langfuse\_url](#output\_langfuse\_url) | Public URL of the Langfuse web UI. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where Langfuse is deployed. |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 bucket used for Langfuse blob storage. |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 bucket used for Langfuse blob storage. |
<!-- END_TF_DOCS -->

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
