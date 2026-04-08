# ------------------------------------------------------------------------------
# Cognito App Client – created only when var.cognito_enabled = true.
#
# The ALB authenticator is configured via annotations in ingress.tf.
# Only a new App Client is created here; the User Pool itself must already
# exist (pass its ID and ARN via variables).
# ------------------------------------------------------------------------------

locals {
  app_url = "https://${var.dns_record_name}.${var.hosted_zone_name}"
}

resource "aws_cognito_user_pool_client" "langfuse" {
  count = var.cognito_enabled ? 1 : 0

  name         = "${var.identifier}-langfuse"
  user_pool_id = var.cognito_user_pool_id

  generate_secret = true

  access_token_validity = 60
  id_token_validity     = 60

  token_validity_units {
    access_token = "minutes"
    id_token     = "minutes"
  }

  supported_identity_providers = var.cognito_identity_providers

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  callback_urls = concat(
    ["${local.app_url}/oauth2/idpresponse"],
    var.cognito_extra_callback_urls,
  )

  logout_urls = concat(
    ["${local.app_url}/logged-out"],
    var.cognito_extra_logout_urls,
  )

  read_attributes  = ["email", "name"]
  write_attributes = ["email", "name"]
}
