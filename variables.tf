# ------------------------------------------------------------------------------
# Required – AWS context
# ------------------------------------------------------------------------------

variable "aws_account_id" {
  description = "AWS account ID where resources will be deployed."
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources will be deployed (e.g. us-east-1)."
  type        = string
}

variable "identifier" {
  description = "Unique identifier used to name AWS resources (e.g. myapp-prod). Must be lowercase alphanumeric with hyphens."
  type        = string
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, staging, prod). Used in resource tags."
  type        = string
}

# ------------------------------------------------------------------------------
# Required – Networking
# ------------------------------------------------------------------------------

variable "main_private_subnet_ids" {
  description = "Private subnet IDs. Used for internal EKS node placement."
  type        = list(string)
}

variable "main_public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing ALB."
  type        = list(string)
}

# ------------------------------------------------------------------------------
# Required – EKS
# ------------------------------------------------------------------------------

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster."
  type        = string
}

variable "eks_openid_connect_provider_url" {
  description = "OIDC provider URL of the EKS cluster (e.g. https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE)."
  type        = string
}

variable "eks_openid_connect_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster."
  type        = string
}

variable "node_instance_role_name" {
  description = "Name of the IAM role attached to EKS worker nodes. Required by Karpenter EC2NodeClass."
  type        = string
}

# ------------------------------------------------------------------------------
# Required – Storage
# ------------------------------------------------------------------------------

variable "efs_file_system_id" {
  description = "ID of the existing EFS file system used for PostgreSQL and Redis persistent volumes."
  type        = string
}

variable "storage_class_name" {
  description = "Kubernetes StorageClass name backed by EFS CSI driver (e.g. efs)."
  type        = string
}

# ------------------------------------------------------------------------------
# Required – TLS / DNS
# ------------------------------------------------------------------------------

variable "certificate_arn" {
  description = "ARN of the ACM certificate used by the ALB HTTPS listener."
  type        = string
}

variable "hosted_zone_name" {
  description = "Route 53 hosted zone name (e.g. example.com)."
  type        = string
}

variable "dns_record_name" {
  description = "DNS record prefix created in the hosted zone (e.g. langfuse). The full URL will be https://<dns_record_name>.<hosted_zone_name>."
  type        = string
  default     = "langfuse"
}

# ------------------------------------------------------------------------------
# Optional – Langfuse Helm chart
# ------------------------------------------------------------------------------

variable "langfuse_chart_version" {
  description = "Version of the Langfuse Helm chart to deploy. See https://github.com/langfuse/langfuse-k8s/releases."
  type        = string
  default     = "1.5.22"
}

variable "langfuse_web_replicas" {
  description = "Number of Langfuse web pod replicas."
  type        = number
  default     = 1
}

variable "langfuse_worker_replicas" {
  description = "Number of Langfuse worker pod replicas."
  type        = number
  default     = 1
}

variable "langfuse_cpu" {
  description = "CPU request/limit for Langfuse web and worker pods."
  type        = string
  default     = "1"
}

variable "langfuse_memory" {
  description = "Memory request/limit for Langfuse web and worker pods."
  type        = string
  default     = "4Gi"
}

variable "clickhouse_replicas" {
  description = "Number of ClickHouse replicas."
  type        = number
  default     = 1
}

variable "clickhouse_cpu" {
  description = "CPU request for ClickHouse pods."
  type        = string
  default     = "2"
}

variable "clickhouse_memory" {
  description = "Memory request/limit for ClickHouse pods."
  type        = string
  default     = "6Gi"
}

variable "extra_helm_values" {
  description = "Additional raw YAML values to merge into the Langfuse Helm release. Useful for customising sub-charts without forking the module."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# Optional – S3
# ------------------------------------------------------------------------------

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Langfuse blob storage. Defaults to '<identifier>-langfuse'."
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Optional – Karpenter
# ------------------------------------------------------------------------------

variable "node_pool_availability_zones" {
  description = "Availability zones for the Langfuse Karpenter NodePool. Defaults to a, b, c zones of the target region."
  type        = list(string)
  default     = null
}

variable "node_pool_cpu_limit" {
  description = "Maximum CPU units allocatable across all Langfuse nodes."
  type        = number
  default     = 50
}

variable "node_pool_memory_limit" {
  description = "Maximum memory allocatable across all Langfuse nodes."
  type        = string
  default     = "500Gi"
}

variable "node_pool_instance_categories" {
  description = "EC2 instance categories (c = compute, m = general, r = memory) eligible for the Langfuse NodePool."
  type        = list(string)
  default     = ["c", "m", "r"]
}

# ------------------------------------------------------------------------------
# Optional – Cognito SSO
# ------------------------------------------------------------------------------

variable "cognito_enabled" {
  description = "Set to true to front the Langfuse web UI with AWS Cognito SSO via the ALB authenticator. Requires cognito_user_pool_id, cognito_user_pool_arn and cognito_domain."
  type        = bool
  default     = false
}

variable "cognito_user_pool_id" {
  description = "Existing Cognito User Pool ID."
  type        = string
  default     = null
}

variable "cognito_user_pool_arn" {
  description = "ARN of the existing Cognito User Pool."
  type        = string
  default     = null
}

variable "cognito_domain" {
  description = "Cognito hosted-UI domain prefix (e.g. myapp-auth). The full domain is <cognito_domain>.auth.<region>.amazoncognito.com."
  type        = string
  default     = null
}

variable "cognito_identity_providers" {
  description = "List of Cognito identity providers to allow (e.g. ['COGNITO', 'Google', 'my-saml-idp'])."
  type        = list(string)
  default     = ["COGNITO"]
}

variable "cognito_extra_callback_urls" {
  description = "Additional OAuth callback URLs appended to the Cognito App Client (e.g. localhost for dev)."
  type        = list(string)
  default     = []
}

variable "cognito_extra_logout_urls" {
  description = "Additional logout redirect URLs appended to the Cognito App Client."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# Optional – Miscellaneous
# ------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags applied to all AWS resources created by this module."
  type        = map(string)
  default     = {}
}
