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

variable "subnetwork_self_link" {
  type = string
}

variable "portal_image" {
  type        = string
  description = "Bootstrap Portal/Workspace API image"
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "force_destroy_notebook_bucket" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "cloud_build_analysis_sa_email" {
  type        = string
  default     = null
  nullable    = true
  description = "Cloud Build SA allowed to deploy revisions using the Analysis Portal runtime SA."
}

locals {
  prefix = "managed02-${var.environment}"
}

resource "google_service_account" "node" {
  project      = var.project_id
  account_id   = "gke-analysis-node-${var.environment}"
  display_name = "Analysis GKE Autopilot node service account"
}

resource "google_project_iam_member" "node_default_role" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_container_cluster" "analysis" {
  project             = var.project_id
  name                = "gke-analysis-${var.environment}"
  location            = var.region
  enable_autopilot    = true
  network             = var.network_self_link
  subnetwork          = var.subnetwork_self_link
  networking_mode     = "VPC_NATIVE"
  deletion_protection = var.deletion_protection

  ip_allocation_policy {}

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.node.email
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  depends_on = [
    google_project_iam_member.node_default_role,
    google_project_iam_member.node_artifact_reader,
  ]
}

resource "google_storage_bucket" "notebooks" {
  project                     = var.project_id
  name                        = "${var.project_id}-${local.prefix}-analysis-notebooks"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy_notebook_bucket

  versioning {
    enabled = true
  }
}

resource "google_service_account" "jupyter" {
  project      = var.project_id
  account_id   = "jupyter-${var.environment}-02"
  display_name = "Jupyter user workload service account"
}

resource "google_storage_bucket_iam_member" "jupyter_bucket_access" {
  bucket = google_storage_bucket.notebooks.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.jupyter.email}"
}

resource "google_service_account" "portal" {
  project      = var.project_id
  account_id   = "analysis-portal-${var.environment}-02"
  display_name = "Analysis Portal Cloud Run runtime"
}

resource "google_project_iam_member" "portal_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.portal.email}"
}

resource "google_service_account_iam_member" "portal_build_sa_user" {
  count = var.cloud_build_analysis_sa_email != null ? 1 : 0

  service_account_id = google_service_account.portal.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.cloud_build_analysis_sa_email}"
}

resource "google_cloud_run_v2_service" "portal" {
  project             = var.project_id
  name                = "analysis-portal-${var.environment}-02"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.portal.email

    containers {
      image = var.portal_image

      env {
        name  = "GKE_CLUSTER"
        value = google_container_cluster.analysis.name
      }

      env {
        name  = "NOTEBOOK_BUCKET"
        value = google_storage_bucket.notebooks.name
      }
    }
  }
}

output "cluster_name" {
  value = google_container_cluster.analysis.name
}

output "cluster_location" {
  value = google_container_cluster.analysis.location
}

output "cluster_endpoint" {
  value     = google_container_cluster.analysis.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.analysis.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "notebook_bucket" {
  value = google_storage_bucket.notebooks.name
}

output "jupyter_service_account_email" {
  value = google_service_account.jupyter.email
}

output "jupyter_service_account_name" {
  value = google_service_account.jupyter.name
}

output "portal_uri" {
  value = google_cloud_run_v2_service.portal.uri
}
