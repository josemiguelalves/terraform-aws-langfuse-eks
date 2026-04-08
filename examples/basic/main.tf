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
  source  = "josemiguelalves/langfuse-eks/aws"

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

  # --- TLS / DNS ---
  certificate_arn  = var.certificate_arn
  hosted_zone_name = var.hosted_zone_name
  dns_record_name  = "langfuse"
}
