# Changelog

All notable changes to this module will be documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] – 2024-04-08

### Added
- Initial release.
- Helm-based deployment of Langfuse on EKS via the official `langfuse-k8s` chart.
- EFS-backed persistent volumes for PostgreSQL and Redis.
- S3 bucket with lifecycle tiering for blob storage (events, exports, media).
- IRSA-based IAM role with least-privilege S3 access scoped to the module bucket.
- Karpenter `EC2NodeClass` + `NodePool` with configurable instance categories, AZs and resource limits.
- Dual ALB Ingress setup: unauthenticated `/api/public` path + optional Cognito SSO for the web UI.
- Route 53 alias record pointing to the ALB.
- Optional Cognito User Pool Client creation for SSO.
- Auto-generated secrets (PostgreSQL, Redis, ClickHouse passwords; SALT; NEXTAUTH_SECRET; ENCRYPTION_KEY).
- `examples/basic` and `examples/complete`.
- GitHub Actions CI: fmt, validate, terraform-docs diff, tflint, Checkov.
- GitHub Actions release workflow.

[Unreleased]: https://github.com/YOUR_ORG/terraform-aws-langfuse-eks/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/YOUR_ORG/terraform-aws-langfuse-eks/releases/tag/v0.1.0
