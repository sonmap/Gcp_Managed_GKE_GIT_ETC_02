terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_branch_regex" {
  type    = string
  default = "^main$"
}

variable "enable_github_triggers" {
  type        = bool
  default     = false
  description = "Enable only after the GitHub repository is connected to Cloud Build."
}

locals {
  repositories = {
    app-images      = "DOCKER"
    model-images    = "DOCKER"
    notebook-images = "DOCKER"
    python-packages = "PYTHON"
  }

  build_accounts = {
    batch    = "cb-batch-${var.environment}-02"
    l2       = "cb-l2-${var.environment}-02"
    analysis = "cb-analysis-${var.environment}-02"
  }

  common_roles = toset([
    "roles/logging.logWriter",
    "roles/storage.objectViewer",
  ])
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository" "repos" {
  for_each      = local.repositories
  project       = var.project_id
  location      = var.region
  repository_id = each.key
  format        = each.value
}

resource "google_service_account" "build" {
  for_each     = local.build_accounts
  project      = var.project_id
  account_id   = each.value
  display_name = "Managed02 Cloud Build ${each.key} deployer"
}

resource "google_project_iam_member" "common_roles" {
  for_each = {
    for pair in setproduct(keys(local.build_accounts), local.common_roles) :
    "${pair[0]}:${pair[1]}" => {
      account = pair[0]
      role    = pair[1]
    }
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.build[each.value.account].email}"
}

resource "google_project_iam_member" "batch_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.build["batch"].email}"
}

resource "google_project_iam_member" "batch_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.build["batch"].email}"
}

resource "google_project_iam_member" "batch_composer_admin" {
  project = var.project_id
  role    = "roles/composer.admin"
  member  = "serviceAccount:${google_service_account.build["batch"].email}"
}

resource "google_project_iam_member" "l2_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.build["l2"].email}"
}

resource "google_project_iam_member" "l2_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.build["l2"].email}"
}

resource "google_project_iam_member" "analysis_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.build["analysis"].email}"
}

resource "google_project_iam_member" "analysis_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.build["analysis"].email}"
}

resource "google_service_account_iam_member" "cloudbuild_token_creator" {
  for_each = google_service_account.build

  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

resource "google_cloudbuild_trigger" "batch" {
  count           = var.enable_github_triggers ? 1 : 0
  project         = var.project_id
  location        = var.region
  name            = "managed02-batch-main"
  service_account = google_service_account.build["batch"].name
  filename        = "cloudbuild/batch.yaml"
  included_files  = ["batch/**", "composer/**", "cloudbuild/batch.yaml"]

  github {
    owner = var.github_owner
    name  = var.github_repo

    push {
      branch = var.github_branch_regex
    }
  }
}

resource "google_cloudbuild_trigger" "l2" {
  count           = var.enable_github_triggers ? 1 : 0
  project         = var.project_id
  location        = var.region
  name            = "managed02-l2-main"
  service_account = google_service_account.build["l2"].name
  filename        = "cloudbuild/l2.yaml"
  included_files  = ["model-src/**", "cloudbuild/l2.yaml"]

  github {
    owner = var.github_owner
    name  = var.github_repo

    push {
      branch = var.github_branch_regex
    }
  }
}

resource "google_cloudbuild_trigger" "analysis" {
  count           = var.enable_github_triggers ? 1 : 0
  project         = var.project_id
  location        = var.region
  name            = "managed02-analysis-main"
  service_account = google_service_account.build["analysis"].name
  filename        = "cloudbuild/analysis.yaml"
  included_files  = ["analysis/**", "jupyterhub/**", "cloudbuild/analysis.yaml"]

  github {
    owner = var.github_owner
    name  = var.github_repo

    push {
      branch = var.github_branch_regex
    }
  }
}

output "artifact_repositories" {
  value = {
    for key, repo in google_artifact_registry_repository.repos :
    key => repo.repository_id
  }
}

output "build_service_accounts" {
  value = {
    for key, sa in google_service_account.build :
    key => sa.email
  }
}
