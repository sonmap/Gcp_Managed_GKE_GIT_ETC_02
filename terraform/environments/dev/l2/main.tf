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
variable "tf_state_bucket" { type = string }
variable "deletion_protection" {
  type    = bool
  default = false
}

data "terraform_remote_state" "common" {
  backend = "gcs"

  config = {
    bucket = var.tf_state_bucket
    prefix = "gcp-managed-02/${var.environment}/common"
  }
}

module "l2" {
  source = "../../../modules/l2"

  project_id           = var.project_id
  region               = var.region
  environment          = var.environment
  network_self_link    = data.terraform_remote_state.common.outputs.network_self_link
  subnetwork_self_link = data.terraform_remote_state.common.outputs.subnetwork_self_link
  deletion_protection  = var.deletion_protection
}

output "cluster_name" { value = module.l2.cluster_name }
output "cluster_location" { value = module.l2.cluster_location }
