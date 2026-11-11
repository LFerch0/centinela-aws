terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Vacío a propósito: los datos van en backend.hcl.
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Proyecto   = var.proyecto
      Gestionado = "terraform"
    }
  }
}

data "aws_caller_identity" "actual" {}
data "aws_partition" "actual" {}
data "aws_region" "actual" {}

locals {
  nombre    = "centinela"
  cuenta    = data.aws_caller_identity.actual.account_id
  particion = data.aws_partition.actual.partition
  region    = data.aws_region.actual.region
}