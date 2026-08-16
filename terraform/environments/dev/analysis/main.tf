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
variable "force_destroy_notebook_bucket" {
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

module "analysis" {
  source = "../../../modules/analysis"

  project_id                    = var.project_id
  region                        = var.region
  environment                   = var.environment
  network_self_link             = data.terraform_remote_state.common.outputs.network_self_link
  subnetwork_self_link          = data.terraform_remote_state.common.outputs.subnetwork_self_link
  force_destroy_notebook_bucket = var.force_destroy_notebook_bucket
}

output "analysis_cluster_name" {
  value = module.analysis.cluster_name
}

output "analysis_cluster_location" {
  value = module.analysis.cluster_location
}

output "analysis_cluster_endpoint" {
  value     = module.analysis.cluster_endpoint
  sensitive = true
}

output "analysis_cluster_ca_certificate" {
  value     = module.analysis.cluster_ca_certificate
  sensitive = true
}

output "notebook_bucket" {
  value = module.analysis.notebook_bucket
}

output "jupyter_service_account_email" {
  value = module.analysis.jupyter_service_account_email
}

output "jupyter_service_account_name" {
  value = module.analysis.jupyter_service_account_name
}

output "portal_uri" {
  value = module.analysis.portal_uri
}
