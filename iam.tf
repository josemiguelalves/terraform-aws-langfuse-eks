# ------------------------------------------------------------------------------
# Kubernetes RBAC – ClusterRole + ClusterRoleBinding for the Langfuse user
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "langfuse_cluster_role" {
  force_new = true

  yaml_body = <<-YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: langfuse-role
rules:
  - apiGroups: ["*", ""]
    resources: ["*", ""]
    verbs: ["*", ""]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: langfuse-role-binding
subjects:
  - kind: User
    name: ${local.cluster_user}
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: langfuse-role
  apiGroup: rbac.authorization.k8s.io
YAML
}

# ------------------------------------------------------------------------------
# IRSA – trust policy scoped to the Langfuse service account
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "langfuse_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_openid_connect_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.namespace}:${local.service_account}"]
    }

    principals {
      identifiers = [var.eks_openid_connect_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "langfuse" {
  name               = "${var.identifier}-langfuse-irsa"
  assume_role_policy = data.aws_iam_policy_document.langfuse_trust.json
  tags               = local.common_tags
}

# ------------------------------------------------------------------------------
# S3 policy – scoped to the Langfuse bucket only
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "langfuse_s3" {
  statement {
    sid    = "LangfuseS3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.langfuse.arn,
      "${aws_s3_bucket.langfuse.arn}/*",
    ]
  }

  statement {
    sid    = "LangfuseS3KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    # Scope to specific CMK ARNs via var.tags if required; wildcard is safe
    # when the bucket does not use a customer-managed KMS key.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "langfuse_s3" {
  name   = "${var.identifier}-langfuse-s3"
  policy = data.aws_iam_policy_document.langfuse_s3.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "langfuse_s3" {
  role       = aws_iam_role.langfuse.name
  policy_arn = aws_iam_policy.langfuse_s3.arn
}

# ------------------------------------------------------------------------------
# Kubernetes Service Account (IRSA annotation)
# Replaces the eksctl-based service account creation.
# ------------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "langfuse" {
  depends_on = [
    kubernetes_namespace_v1.langfuse,
    aws_iam_role.langfuse,
  ]

  metadata {
    name      = local.service_account
    namespace = kubernetes_namespace_v1.langfuse.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.langfuse.arn
    }
  }
}

# ------------------------------------------------------------------------------
# EKS Access Entry – maps the IRSA role to the Langfuse RBAC user.
# Requires the EKS cluster to use the "API" or "API_AND_CONFIG_MAP" auth mode
# (the default for clusters created after Dec 2023).
#
# For legacy clusters still using only the aws-auth ConfigMap, replace this
# resource with a null_resource that calls:
#   eksctl create iamidentitymapping ...
# ------------------------------------------------------------------------------

resource "aws_eks_access_entry" "langfuse" {
  cluster_name      = var.eks_cluster_name
  principal_arn     = aws_iam_role.langfuse.arn
  kubernetes_groups = [local.cluster_user]
  type              = "STANDARD"

  tags = local.common_tags
}
