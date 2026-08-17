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

variable "network_cidr" {
  type = string
}

locals {
  prefix = "managed02-${var.environment}"

  services = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "composer.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])
}

resource "google_project_service" "apis" {
  for_each           = local.services
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = "${local.prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "main" {
  project                  = var.project_id
  name                     = "${local.prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.network_cidr
  private_ip_google_access = true
}

resource "google_compute_router" "nat_router" {
  project = var.project_id
  name    = "${local.prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "nat" {
  project = var.project_id
  name    = "${local.prefix}-nat"
  router  = google_compute_router.nat_router.name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

output "network_name" {
  value = google_compute_network.main.name
}

output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "subnetwork_name" {
  value = google_compute_subnetwork.main.name
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.main.self_link
}
