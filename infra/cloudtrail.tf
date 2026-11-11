locals {
  nombre_trail = "${local.nombre}-trail"
  arn_trail    = "arn:${local.particion}:cloudtrail:${local.region}:${local.cuenta}:trail/${local.nombre_trail}"
}

# Bucket privado donde CloudTrail guarda los logs
resource "aws_s3_bucket" "trail" {
  bucket        = "${local.nombre}-cloudtrail-${local.cuenta}"
  force_destroy = true # Permite borrarlo con destroy aunque tenga logs
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Los logs se borran a los 90 días para no acumular costo
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    id     = "expirar-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

# Política: solo TU trail puede escribir aquí, y solo por HTTPS
data "aws_iam_policy_document" "trail" {
  statement {
    sid       = "CloudTrailRevisaACL"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.arn_trail]
    }
  }

  statement {
    sid       = "CloudTrailEscribeLogs"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${local.cuenta}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.arn_trail]
    }
  }

  statement {
    sid     = "DenegarSinHTTPS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.trail.arn,
      "${aws_s3_bucket.trail.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket     = aws_s3_bucket.trail.id
  policy     = data.aws_iam_policy_document.trail.json
  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# El trail: todas las regiones, eventos globales (IAM, inicio de sesión) y
# validación de integridad, para detectar si alguien altera un log
resource "aws_cloudtrail" "principal" {
  name                          = local.nombre_trail
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Sin esto, Terraform puede crear el trail antes que la política y falla
  depends_on = [aws_s3_bucket_policy.trail]
}