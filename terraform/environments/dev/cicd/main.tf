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
variable "github_owner" { type = string }
variable "github_repo" { type = string }
variable "enable_github_triggers" { type = bool }

module "cicd" {
  source = "../../../modules/cicd"

  project_id             = var.project_id
  region                 = var.region
  environment            = var.environment
  github_owner           = var.github_owner
  github_repo            = var.github_repo
  enable_github_triggers = var.enable_github_triggers
}

output "artifact_repositories" { value = module.cicd.artifact_repositories }
output "build_service_accounts" { value = module.cicd.build_service_accounts }
