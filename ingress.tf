# ------------------------------------------------------------------------------
# ALB Ingress resources
#
# Two Ingress objects share one ALB via the same group.name annotation:
#
#   langfuse-api  (order 100) – /api/public/** passes through with no auth so
#                               SDKs and programmatic clients can ingest traces.
#
#   langfuse-web  (order 200) – / routes to the UI; Cognito auth is applied
#                               when var.cognito_enabled = true.
# ------------------------------------------------------------------------------

locals {
  alb_subnets = join(", ", var.main_public_subnet_ids)
}

resource "kubectl_manifest" "langfuse_api_ingress" {
  depends_on = [
    helm_release.langfuse,
    kubernetes_namespace_v1.langfuse,
  ]

  yaml_body = <<-YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: ${kubernetes_namespace_v1.langfuse.metadata[0].name}
  name: langfuse-api
  annotations:
    alb.ingress.kubernetes.io/group.name: langfuse
    alb.ingress.kubernetes.io/group.order: '100'
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: ${var.certificate_arn}
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/subnets: ${local.alb_subnets}
    alb.ingress.kubernetes.io/auth-type: none
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /api/public
            pathType: Prefix
            backend:
              service:
                name: langfuse-web
                port:
                  number: 80
YAML
}

resource "kubectl_manifest" "langfuse_web_ingress" {
  depends_on = [
    helm_release.langfuse,
    kubernetes_namespace_v1.langfuse,
    kubernetes_persistent_volume.postgresql,
    kubernetes_persistent_volume.redis,
    aws_cognito_user_pool_client.langfuse,
  ]

  yaml_body = <<-YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: ${kubernetes_namespace_v1.langfuse.metadata[0].name}
  name: langfuse-web
  annotations:
    alb.ingress.kubernetes.io/group.name: langfuse
    alb.ingress.kubernetes.io/group.order: '200'
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: ${var.certificate_arn}
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/subnets: ${local.alb_subnets}
    alb.ingress.kubernetes.io/healthcheck-path: /api/public/health
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=300
    ${trimspace(local.cognito_auth_annotations)}
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: langfuse-web
                port:
                  number: 80
YAML
}
