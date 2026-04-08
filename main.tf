locals {
  name      = "langfuse"
  namespace = "langfuse"

  service_account    = "langfuse"
  cluster_user       = "langfuse-cluster-user"
  chart_version      = var.langfuse_chart_version
  chart_repository   = "https://langfuse.github.io/langfuse-k8s"

  s3_bucket_name = var.s3_bucket_name != null ? var.s3_bucket_name : "${var.identifier}-langfuse"

  node_pool_availability_zones = var.node_pool_availability_zones != null ? var.node_pool_availability_zones : [
    "${var.aws_region}a",
    "${var.aws_region}b",
    "${var.aws_region}c",
  ]

  # Cognito auth annotations injected into the web ingress only when enabled.
  cognito_auth_annotations = var.cognito_enabled ? <<-YAML
    alb.ingress.kubernetes.io/auth-type: cognito
    alb.ingress.kubernetes.io/auth-idp-cognito: '${jsonencode({
      userPoolARN      = var.cognito_user_pool_arn
      userPoolClientID = aws_cognito_user_pool_client.langfuse[0].id
      userPoolDomain   = var.cognito_domain
    })}'
    alb.ingress.kubernetes.io/auth-on-unauthenticated-request: authenticate
    alb.ingress.kubernetes.io/auth-scope: openid email profile
    alb.ingress.kubernetes.io/auth-session-cookie-name: AWSELBAuthSessionCookie
    alb.ingress.kubernetes.io/auth-session-timeout: '3600'
  YAML
  : ""

  common_tags = merge(
    {
      "ManagedBy"   = "Terraform"
      "Module"      = "terraform-aws-langfuse-eks"
      "Environment" = var.environment
      "Identifier"  = var.identifier
    },
    var.tags,
  )

  helm_values = <<-EOT
global:
  defaultStorageClass: ${var.storage_class_name}

langfuse:
  salt:
    value: ${random_bytes.salt.base64}
  nextauth:
    secret:
      value: ${random_bytes.nextauth_secret.base64}
  encryptionKey:
    value: ${random_bytes.encryption_key.hex}
  serviceAccount:
    create: false
    name: ${local.service_account}
    annotations:
      eks.amazonaws.com/role-arn: ${aws_iam_role.langfuse.arn}
  nodeSelector:
    provisioner: ${local.name}
  tolerations:
    - effect: NoSchedule
      key: storageType
      value: efs
  resources:
    limits:
      cpu: "${var.langfuse_cpu}"
      memory: "${var.langfuse_memory}"
    requests:
      cpu: "${var.langfuse_cpu}"
      memory: "${var.langfuse_memory}"
  web:
    replicas: ${var.langfuse_web_replicas}
    livenessProbe:
      initialDelaySeconds: 60
    readinessProbe:
      initialDelaySeconds: 60
    service:
      type: NodePort
      externalPort: 80
  worker:
    replicas: ${var.langfuse_worker_replicas}

postgresql:
  deploy: true
  auth:
    username: langfuse
    database: langfuse
    password: ${random_password.postgresql.result}
  resourcesPreset: "none"
  primary:
    tolerations:
      - operator: Equal
        key: storageType
        value: efs
        effect: NoSchedule
    nodeSelector:
      provisioner: ${local.name}
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "1"
        memory: "2Gi"
    startupProbe:
      enabled: true
      initialDelaySeconds: 30
      periodSeconds: 30
      failureThreshold: 30
      timeoutSeconds: 5
    livenessProbe:
      enabled: true
      initialDelaySeconds: 60
      periodSeconds: 30
      failureThreshold: 6
      timeoutSeconds: 5

clickhouse:
  auth:
    password: ${random_password.clickhouse.result}
  replicaCount: ${var.clickhouse_replicas}
  resourcesPreset: "none"
  persistence:
    storageClass: gp3
  extraOverrides: |
    <clickhouse>
      <trace_log>
        <max_size_rows>500000</max_size_rows>
        <reserved_size_rows>100000</reserved_size_rows>
      </trace_log>
      <asynchronous_metric_log>
        <max_size_rows>500000</max_size_rows>
        <reserved_size_rows>100000</reserved_size_rows>
      </asynchronous_metric_log>
      <metric_log>
        <max_size_rows>500000</max_size_rows>
        <reserved_size_rows>100000</reserved_size_rows>
      </metric_log>
      <query_log>
        <max_size_rows>500000</max_size_rows>
        <reserved_size_rows>100000</reserved_size_rows>
      </query_log>
      <text_log>
        <max_size_rows>500000</max_size_rows>
        <reserved_size_rows>100000</reserved_size_rows>
      </text_log>
      <opentelemetry_span_log>
        <max_size_rows>500000</max_size_rows>
        <reserved_size_rows>100000</reserved_size_rows>
      </opentelemetry_span_log>
    </clickhouse>
  tolerations:
    - operator: Equal
      key: storageType
      value: efs
      effect: NoSchedule
  nodeSelector:
    provisioner: ${local.name}
  resources:
    limits:
      memory: "${var.clickhouse_memory}"
    requests:
      cpu: "${var.clickhouse_cpu}"
      memory: "${var.clickhouse_memory}"
  startupProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 30
    failureThreshold: 30
    timeoutSeconds: 5
  livenessProbe:
    enabled: true
    initialDelaySeconds: 60
    periodSeconds: 30
    failureThreshold: 6
    timeoutSeconds: 5
  zookeeper:
    replicaCount: ${var.clickhouse_replicas}
    resourcesPreset: "none"
    persistence:
      storageClass: gp3
    tolerations:
      - operator: Equal
        key: storageType
        value: efs
        effect: NoSchedule
    nodeSelector:
      provisioner: ${local.name}
    resources:
      limits:
        memory: "4Gi"
      requests:
        cpu: "1"
        memory: "2Gi"

redis:
  deploy: true
  auth:
    password: ${random_password.redis.result}
  primary:
    tolerations:
      - operator: Equal
        key: storageType
        value: efs
        effect: NoSchedule
    nodeSelector:
      provisioner: ${local.name}
  resources:
    limits:
      memory: "4Gi"
    requests:
      cpu: "1"
      memory: "2Gi"

s3:
  deploy: false
  bucket: ${aws_s3_bucket.langfuse.id}
  region: ${var.aws_region}
  forcePathStyle: false
  eventUpload:
    prefix: "events/"
  batchExport:
    prefix: "exports/"
  mediaUpload:
    prefix: "media/"
EOT
}

# ------------------------------------------------------------------------------
# kubeconfig refresh
# ------------------------------------------------------------------------------

resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command     = "aws eks update-kubeconfig --name ${var.eks_cluster_name} --region ${var.aws_region}"
    interpreter = ["bash", "-c"]
  }

  triggers = {
    cluster_name = var.eks_cluster_name
    aws_region   = var.aws_region
  }
}

# ------------------------------------------------------------------------------
# Kubernetes namespace
# ------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "langfuse" {
  depends_on = [
    null_resource.configure_kubectl,
    kubectl_manifest.langfuse_cluster_role,
  ]

  metadata {
    name = local.namespace
  }

  timeouts {
    delete = "15m"
  }
}

# ------------------------------------------------------------------------------
# Helm release
# ------------------------------------------------------------------------------

resource "helm_release" "langfuse" {
  depends_on = [
    null_resource.configure_kubectl,
    kubernetes_namespace_v1.langfuse,
    kubernetes_service_account_v1.langfuse,
    aws_iam_role.langfuse,
  ]

  chart            = local.name
  create_namespace = false
  namespace        = kubernetes_namespace_v1.langfuse.metadata[0].name
  name             = local.name
  version          = local.chart_version
  repository       = local.chart_repository
  force_update     = true
  cleanup_on_fail  = true
  recreate_pods    = true
  wait             = false
  timeout          = 900

  values = compact([local.helm_values, var.extra_helm_values])
}
