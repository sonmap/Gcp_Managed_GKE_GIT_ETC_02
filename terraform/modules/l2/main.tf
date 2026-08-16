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

variable "deletion_protection" {
  type    = bool
  default = false
}

resource "google_service_account" "node" {
  project      = var.project_id
  account_id   = "gke-l2-node-${var.environment}"
  display_name = "L2 GKE Autopilot node service account"
}

resource "google_project_iam_member" "node_default_role" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_container_cluster" "l2" {
  project             = var.project_id
  name                = "gke-l2-${var.environment}"
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
    google_project_iam_member.artifact_reader,
  ]
}

output "cluster_name" {
  value = google_container_cluster.l2.name
}

output "cluster_location" {
  value = google_container_cluster.l2.location
}

output "cluster_endpoint" {
  value     = google_container_cluster.l2.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.l2.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "node_service_account_email" {
  value = google_service_account.node.email
}
