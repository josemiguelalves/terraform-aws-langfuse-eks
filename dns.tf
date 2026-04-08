# ------------------------------------------------------------------------------
# Route 53 – alias record pointing to the ALB created by the Ingress controller.
# The ALB is discovered by its ingress.k8s.aws tags set by the AWS LBC.
# ------------------------------------------------------------------------------

data "aws_lb" "langfuse" {
  tags = {
    "ingress.k8s.aws/stack"    = "langfuse"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [
    kubectl_manifest.langfuse_web_ingress,
    kubectl_manifest.langfuse_api_ingress,
    helm_release.langfuse,
  ]
}

data "aws_route53_zone" "langfuse" {
  name         = var.hosted_zone_name
  private_zone = false
}

resource "aws_route53_record" "langfuse" {
  zone_id = data.aws_route53_zone.langfuse.zone_id
  name    = var.dns_record_name
  type    = "A"

  alias {
    name                   = data.aws_lb.langfuse.dns_name
    zone_id                = data.aws_lb.langfuse.zone_id
    evaluate_target_health = false
  }
}
