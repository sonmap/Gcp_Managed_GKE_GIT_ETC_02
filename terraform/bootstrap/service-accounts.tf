variable "environment" {
  type        = string
  description = "Environment name used in Terraform Cloud Build service account IDs"
  default     = "dev"
}

variable "service_account_suffix" {
  type        = string
  description = "Suffix used in Terraform Cloud Build service account IDs"
  default     = "02"
}

locals {
  terraform_build_accounts = {
    common   = "cb-tf-common-${var.environment}-${var.service_account_suffix}"
    cicd     = "cb-tf-cicd-${var.environment}-${var.service_account_suffix}"
    l2       = "cb-tf-l2-${var.environment}-${var.service_account_suffix}"
    batch    = "cb-tf-batch-${var.environment}-${var.service_account_suffix}"
    analysis = "cb-tf-analysis-${var.environment}-${var.service_account_suffix}"
    jupyter  = "cb-tf-jupyter-${var.environment}-${var.service_account_suffix}"
  }

  # Baseline permissions required by every Terraform Cloud Build execution.
  # Stage-specific resource permissions are granted separately below or when
  # the corresponding stage is enabled, to avoid Owner/Editor style access.
  terraform_build_baseline_roles = toset([
    "roles/logging.logWriter",
    "roles/storage.objectViewer",
  ])
}

resource "google_service_account" "terraform_build" {
  for_each = local.terraform_build_accounts

  project      = var.project_id
  account_id   = each.value
  display_name = "Terraform Cloud Build ${each.key} (${var.environment})"
}

resource "google_project_iam_member" "terraform_build_baseline" {
  for_each = {
    for pair in setproduct(keys(local.terraform_build_accounts), local.terraform_build_baseline_roles) :
    "${pair[0]}:${pair[1]}" => {
      account = pair[0]
      role    = pair[1]
    }
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.terraform_build[each.value.account].email}"
}

# All Terraform stage build accounts need read/write access to their remote
# state objects. The permission is scoped to the Terraform state bucket.
resource "google_storage_bucket_iam_member" "terraform_state_access" {
  for_each = google_service_account.terraform_build

  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value.email}"
}

# Common stage manages project APIs and the shared VPC/Subnet/Router/NAT.
resource "google_project_iam_member" "terraform_common_service_usage_admin" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${google_service_account.terraform_build["common"].email}"
}

resource "google_project_iam_member" "terraform_common_network_admin" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.terraform_build["common"].email}"
}

output "terraform_build_service_accounts" {
  value = {
    for stage, sa in google_service_account.terraform_build : stage => sa.email
  }
}
