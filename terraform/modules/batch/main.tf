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

variable "network_self_link" {
  type = string
}

variable "enable_cloud_sql" {
  type    = bool
  default = false
}

variable "enable_composer" {
  type    = bool
  default = true
}

variable "enable_batch_api" {
  type    = bool
  default = true
}

variable "composer_image_version" {
  type    = string
  default = "composer-3-airflow-2.11.1-build.11"
}

variable "batch_api_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "db_version" {
  type    = string
  default = "POSTGRES_16"
}

variable "db_tier" {
  type    = string
  default = "db-custom-1-3840"
}

variable "cloud_build_batch_sa_email" {
  type        = string
  default     = null
  nullable    = true
  description = "Cloud Build SA allowed to deploy revisions using the Batch API runtime SA."
}

locals {
  prefix = "managed02-${var.environment}"
}

resource "google_service_account" "composer" {
  count        = var.enable_composer ? 1 : 0
  project      = var.project_id
  account_id   = "composer-${var.environment}-02"
  display_name = "Managed02 Composer service account"
}

resource "google_project_iam_member" "composer_worker" {
  count   = var.enable_composer ? 1 : 0
  project = var.project_id
  role    = "roles/composer.worker"
  member  = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_project_iam_member" "composer_gke_developer" {
  count   = var.enable_composer ? 1 : 0
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_composer_environment" "main" {
  count   = var.enable_composer ? 1 : 0
  project = var.project_id
  name    = "managed02-airflow-${var.environment}"
  region  = var.region

  config {
    software_config {
      image_version = var.composer_image_version
    }

    node_config {
      service_account = google_service_account.composer[0].email
    }
  }

  depends_on = [
    google_project_iam_member.composer_worker,
    google_project_iam_member.composer_gke_developer,
  ]
}

resource "google_compute_global_address" "private_service_range" {
  count         = var.enable_cloud_sql ? 1 : 0
  project       = var.project_id
  name          = "${local.prefix}-batch-private-service-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.enable_cloud_sql ? 1 : 0
  network                 = var.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range[0].name]
}

resource "google_sql_database_instance" "metadata" {
  count               = var.enable_cloud_sql ? 1 : 0
  project             = var.project_id
  name                = "${local.prefix}-batch-db"
  region              = var.region
  database_version    = var.db_version
  deletion_protection = false

  settings {
    tier = var.db_tier

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_self_link
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_service_account" "batch_runtime" {
  count        = var.enable_batch_api ? 1 : 0
  project      = var.project_id
  account_id   = "batch-api-${var.environment}-02"
  display_name = "Managed02 Batch API runtime"
}

resource "google_service_account_iam_member" "batch_build_sa_user" {
  count = var.enable_batch_api && var.cloud_build_batch_sa_email != null ? 1 : 0

  service_account_id = google_service_account.batch_runtime[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.cloud_build_batch_sa_email}"
}

resource "google_cloud_run_v2_service" "batch_api" {
  count               = var.enable_batch_api ? 1 : 0
  project             = var.project_id
  name                = "batch-api-${var.environment}-02"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.batch_runtime[0].email

    containers {
      image = var.batch_api_image

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
    }
  }
}

output "composer_environment_name" {
  value = try(google_composer_environment.main[0].name, null)
}

output "composer_service_account_email" {
  value = try(google_service_account.composer[0].email, null)
}

output "batch_api_service_name" {
  value = try(google_cloud_run_v2_service.batch_api[0].name, null)
}

output "batch_api_uri" {
  value = try(google_cloud_run_v2_service.batch_api[0].uri, null)
}

output "batch_runtime_service_account_email" {
  value = try(google_service_account.batch_runtime[0].email, null)
}

output "cloud_sql_instance_name" {
  value = try(google_sql_database_instance.metadata[0].name, null)
}
