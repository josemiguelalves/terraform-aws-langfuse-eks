# ------------------------------------------------------------------------------
# EFS-backed storage for PostgreSQL and Redis
#
# ClickHouse and ZooKeeper use EBS gp3 via dynamic provisioning
# (storageClass: gp3 in the Helm values).
# ------------------------------------------------------------------------------

resource "aws_efs_access_point" "postgresql" {
  file_system_id = var.efs_file_system_id

  root_directory {
    path = "/langfuse/postgresql"
    creation_info {
      owner_gid   = 1001
      owner_uid   = 1001
      permissions = "0755"
    }
  }

  posix_user {
    gid = 1001
    uid = 1001
  }

  tags = merge(local.common_tags, { Name = "${var.identifier}-langfuse-postgresql" })
}

resource "aws_efs_access_point" "redis" {
  file_system_id = var.efs_file_system_id

  root_directory {
    path = "/langfuse/redis"
    creation_info {
      owner_gid   = 1001
      owner_uid   = 1001
      permissions = "0755"
    }
  }

  posix_user {
    gid = 1001
    uid = 1001
  }

  tags = merge(local.common_tags, { Name = "${var.identifier}-langfuse-redis" })
}

# ------------------------------------------------------------------------------
# Persistent Volumes (EFS-backed) – pre-provisioned so the Helm chart can bind
# PVCs deterministically.
# ------------------------------------------------------------------------------

resource "kubernetes_persistent_volume" "postgresql" {
  metadata {
    name = "data-langfuse-postgresql-0"
  }

  spec {
    capacity                         = { storage = "8Gi" }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = var.storage_class_name

    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = "${var.efs_file_system_id}::${aws_efs_access_point.postgresql.id}"
      }
    }

    claim_ref {
      name      = "data-langfuse-postgresql-0"
      namespace = kubernetes_namespace_v1.langfuse.metadata[0].name
    }
  }
}

resource "kubernetes_persistent_volume" "redis" {
  metadata {
    name = "valkey-data-langfuse-redis-primary-0"
  }

  spec {
    capacity                         = { storage = "8Gi" }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = var.storage_class_name

    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = "${var.efs_file_system_id}::${aws_efs_access_point.redis.id}"
      }
    }

    claim_ref {
      name      = "valkey-data-langfuse-redis-primary-0"
      namespace = kubernetes_namespace_v1.langfuse.metadata[0].name
    }
  }
}
