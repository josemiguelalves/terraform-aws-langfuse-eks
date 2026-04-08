output "langfuse_url" {
  description = "Public URL of the Langfuse web UI."
  value       = "https://${var.dns_record_name}.${var.hosted_zone_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer created by the AWS Load Balancer Controller."
  value       = data.aws_lb.langfuse.dns_name
}

output "namespace" {
  description = "Kubernetes namespace where Langfuse is deployed."
  value       = kubernetes_namespace_v1.langfuse.metadata[0].name
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the Langfuse Kubernetes service account (IRSA)."
  value       = aws_iam_role.langfuse.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for Langfuse blob storage."
  value       = aws_s3_bucket.langfuse.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for Langfuse blob storage."
  value       = aws_s3_bucket.langfuse.arn
}

output "cognito_client_id" {
  description = "Cognito App Client ID. Only populated when cognito_enabled = true."
  value       = var.cognito_enabled ? aws_cognito_user_pool_client.langfuse[0].id : null
}

output "helm_release_status" {
  description = "Status of the Langfuse Helm release."
  value       = helm_release.langfuse.status
}
