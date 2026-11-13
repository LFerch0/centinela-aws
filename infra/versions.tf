terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
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
variable "limite_presupuesto_usd" {
  description = "Presupuesto mensual en USD, sin restar créditos."
  type        = number
  default     = 5
}