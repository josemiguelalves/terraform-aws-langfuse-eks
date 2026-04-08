provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

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

module "langfuse" {
  source = "../../" # replace with registry source once published

  # --- AWS context ---
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
  identifier     = "myapp-prod"
  environment    = "prod"

  # --- EKS ---
  eks_cluster_name                = var.eks_cluster_name
  eks_openid_connect_provider_url = var.eks_openid_connect_provider_url
  eks_openid_connect_provider_arn = var.eks_openid_connect_provider_arn
  node_instance_role_name         = var.node_instance_role_name

  # --- Networking ---
  main_private_subnet_ids = var.main_private_subnet_ids
  main_public_subnet_ids  = var.main_public_subnet_ids

  # --- Storage ---
  efs_file_system_id = var.efs_file_system_id
  storage_class_name = "efs"
  s3_bucket_name     = "myapp-prod-langfuse-blobs"

  # --- TLS / DNS ---
  certificate_arn  = var.certificate_arn
  hosted_zone_name = var.hosted_zone_name
  dns_record_name  = "langfuse"

  # --- Langfuse sizing ---
  langfuse_chart_version   = "1.5.22"
  langfuse_web_replicas    = 2
  langfuse_worker_replicas = 2
  langfuse_cpu             = "2"
  langfuse_memory          = "8Gi"
  clickhouse_replicas      = 1
  clickhouse_cpu           = "4"
  clickhouse_memory        = "8Gi"

  # --- Karpenter ---
  node_pool_availability_zones  = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  node_pool_cpu_limit           = 100
  node_pool_memory_limit        = "1000Gi"
  node_pool_instance_categories = ["c", "m", "r"]

  # --- Cognito SSO ---
  cognito_enabled            = true
  cognito_user_pool_id       = var.cognito_user_pool_id
  cognito_user_pool_arn      = var.cognito_user_pool_arn
  cognito_domain             = var.cognito_domain
  cognito_identity_providers = ["COGNITO"]
  cognito_extra_callback_urls = [
    "http://localhost:3000/callback", # local dev
  ]
  cognito_extra_logout_urls = [
    "http://localhost:3000",
  ]

  tags = {
    "Project"    = "myapp"
    "CostCenter" = "platform"
  }
}
