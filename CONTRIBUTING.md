# Contributing

Contributions are welcome! Please follow this workflow.

## Getting started

```bash
git clone https://github.com/josemiguelalves/terraform-aws-langfuse-eks
cd terraform-aws-langfuse-eks
```

### Tools

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.3 | Plan / apply |
| [terraform-docs](https://terraform-docs.io) | >= 0.17 | Regenerate README docs |
| [tflint](https://github.com/terraform-linters/tflint) | >= 0.50 | Linting |
| [Checkov](https://www.checkov.io) | >= 3 | Security scanning |

Install all tools via [mise](https://mise.jdx.dev):

```bash
mise install
```

## Workflow

1. Fork the repo and create a feature branch from `main`.
2. Make your changes.
3. Run `terraform fmt -recursive` and `terraform validate` in the root and each example.
4. Regenerate docs: `terraform-docs .`
5. Open a PR – CI will run automatically.

## Pull request checklist

- [ ] `terraform fmt -recursive` passes
- [ ] `terraform validate` passes for the module and all examples
- [ ] README is up-to-date (`terraform-docs .`)
- [ ] CHANGELOG entry added under `[Unreleased]`
- [ ] No secrets or credentials committed

## Versioning

This module follows [Semantic Versioning](https://semver.org). Releases are tagged `vMAJOR.MINOR.PATCH` on `main` and published automatically by the release workflow.

| Change type | Version bump |
|---|---|
| Breaking variable rename / resource replacement | MAJOR |
| New optional variable or resource | MINOR |
| Bug fix with no API changes | PATCH |

## Reporting issues

Please open a GitHub issue with:
- Terraform and AWS provider versions
- Minimal reproduction snippet
- Expected vs actual behaviour
