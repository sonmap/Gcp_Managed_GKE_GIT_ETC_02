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
variable "enable_cloud_sql" { type = bool }
variable "enable_composer" { type = bool }
variable "enable_batch_api" { type = bool }
variable "composer_image_version" { type = string }

data "terraform_remote_state" "common" {
  backend = "gcs"

  config = {
    bucket = var.tf_state_bucket
    prefix = "gcp-managed-02/${var.environment}/common"
  }
}

module "batch" {
  source = "../../../modules/batch"

  project_id             = var.project_id
  region                 = var.region
  environment            = var.environment
  network_self_link      = data.terraform_remote_state.common.outputs.network_self_link
  enable_cloud_sql       = var.enable_cloud_sql
  enable_composer        = var.enable_composer
  enable_batch_api       = var.enable_batch_api
  composer_image_version = var.composer_image_version
}

output "composer_environment_name" { value = module.batch.composer_environment_name }
output "batch_api_uri" { value = module.batch.batch_api_uri }
output "batch_runtime_service_account_email" { value = module.batch.batch_runtime_service_account_email }
output "cloud_sql_instance_name" { value = module.batch.cloud_sql_instance_name }
