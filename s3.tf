# ------------------------------------------------------------------------------
# S3 bucket – Langfuse blob storage (events, exports, media)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "langfuse" {
  bucket = local.s3_bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "langfuse" {
  bucket = aws_s3_bucket.langfuse.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "langfuse" {
  bucket = aws_s3_bucket.langfuse.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tiered storage lifecycle: IA after 90 days, Glacier IR after 180 days.
resource "aws_s3_bucket_lifecycle_configuration" "langfuse" {
  bucket = aws_s3_bucket.langfuse.id

  rule {
    id     = "langfuse-tiering"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }
  }
}
