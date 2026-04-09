# ------------------------------------------------------------------------------
# Random secrets – generated once and stored in Kubernetes Secret + tfstate.
# Rotate by tainting the relevant resource.
# ------------------------------------------------------------------------------

resource "random_password" "postgresql" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "random_password" "redis" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "random_password" "clickhouse" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# SALT – must be at least 256 bits (32 bytes)
# https://langfuse.com/self-hosting/configuration#core-infrastructure-settings
resource "random_bytes" "salt" {
  length = 32
}

# NEXTAUTH_SECRET – must be at least 256 bits (32 bytes)
resource "random_bytes" "nextauth_secret" {
  length = 32
}

# ENCRYPTION_KEY – must be exactly 256 bits (32 bytes)
resource "random_bytes" "encryption_key" {
  length = 32
}

# ------------------------------------------------------------------------------
# Kubernetes Secret – makes all credentials available inside the cluster.
# The Helm chart references these via secretKeyRef.
# ------------------------------------------------------------------------------

resource "kubernetes_secret" "langfuse" {
  depends_on = [kubernetes_namespace_v1.langfuse]

  metadata {
    name      = "langfuse-credentials"
    namespace = kubernetes_namespace_v1.langfuse.metadata[0].name
  }

  data = {
    "postgresql-password" = random_password.postgresql.result
    "redis-password"      = random_password.redis.result
    "clickhouse-password" = random_password.clickhouse.result
    "salt"                = random_bytes.salt.base64
    "nextauth-secret"     = random_bytes.nextauth_secret.base64
    "encryption-key"      = random_bytes.encryption_key.hex
  }
}
