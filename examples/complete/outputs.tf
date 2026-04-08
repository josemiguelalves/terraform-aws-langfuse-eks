output "langfuse_url" {
  value = module.langfuse.langfuse_url
}

output "alb_dns_name" {
  value = module.langfuse.alb_dns_name
}

output "s3_bucket_name" {
  value = module.langfuse.s3_bucket_name
}

output "iam_role_arn" {
  value = module.langfuse.iam_role_arn
}

output "cognito_client_id" {
  value = module.langfuse.cognito_client_id
}
