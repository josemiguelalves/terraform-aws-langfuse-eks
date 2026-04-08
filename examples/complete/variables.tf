variable "aws_account_id" { type = string }
variable "aws_region" { type = string; default = "us-east-1" }
variable "eks_cluster_name" { type = string }
variable "eks_openid_connect_provider_url" { type = string }
variable "eks_openid_connect_provider_arn" { type = string }
variable "node_instance_role_name" { type = string }
variable "main_private_subnet_ids" { type = list(string) }
variable "main_public_subnet_ids" { type = list(string) }
variable "efs_file_system_id" { type = string }
variable "certificate_arn" { type = string }
variable "hosted_zone_name" { type = string }
variable "cognito_user_pool_id" { type = string }
variable "cognito_user_pool_arn" { type = string }
variable "cognito_domain" { type = string }
