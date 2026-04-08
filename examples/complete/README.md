# Complete Example

Deploys Langfuse on EKS with all optional features enabled:

- Cognito SSO fronting the web UI via the ALB authenticator
- HA sizing (2 web + 2 worker replicas)
- Custom Karpenter node pool limits
- S3 bucket with explicit name
- Resource tagging

## Prerequisites

- EKS cluster with Karpenter, AWS Load Balancer Controller and EFS CSI driver installed
- Existing Cognito User Pool with a hosted-UI domain
- ACM certificate and Route 53 hosted zone

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```
