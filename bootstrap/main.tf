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
  # El ID de cuenta hace el nombre único en todo el mundo.
  bucket = "centinela-tfstate-${data.aws_caller_identity.actual.account_id}"

  lifecycle {
    prevent_destroy = true # Terraform se niega a borrarlo por accidente.
  }
}

resource "aws_s3_bucket_versioning" "estado" {
  bucket = aws_s3_bucket.estado.id
  versioning_configuration {
    status = "Enabled" # Si el estado se corrompe, recuperas una versión anterior.
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