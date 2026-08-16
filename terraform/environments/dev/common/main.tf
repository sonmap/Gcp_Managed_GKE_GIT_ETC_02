terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "network_cidr" { type = string }

module "common" {
  source = "../../../modules/common"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  network_cidr = var.network_cidr
}

output "network_name" { value = module.common.network_name }
output "network_self_link" { value = module.common.network_self_link }
output "subnetwork_name" { value = module.common.subnetwork_name }
output "subnetwork_self_link" { value = module.common.subnetwork_self_link }
