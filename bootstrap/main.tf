terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Proyecto   = "centinela-aws"
      Gestionado = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "actual" {}

resource "aws_s3_bucket" "estado" {
  bucket = "centinela-tfstate-${data.aws_caller_identity.actual.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "estado" {
  bucket = aws_s3_bucket.estado.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "estado" {
  bucket                  = aws_s3_bucket.estado.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id
  rule {
    id     = "limpiar-versiones-antiguas"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90 # Versiones anteriores del estado: 90 días para recuperar
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}