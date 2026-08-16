terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
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
variable "jupyterhub_chart_version" {
  type        = string
  default     = null
  nullable    = true
  description = "Pin in production. null installs the current chart version."
}
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

data "google_client_config" "current" {}

module "analysis" {
  source = "../../../modules/analysis"

  project_id                    = var.project_id
  region                        = var.region
  environment                   = var.environment
  network_self_link             = data.terraform_remote_state.common.outputs.network_self_link
  subnetwork_self_link          = data.terraform_remote_state.common.outputs.subnetwork_self_link
  force_destroy_notebook_bucket = var.force_destroy_notebook_bucket
}

provider "kubernetes" {
  host                   = "https://${module.analysis.cluster_endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(module.analysis.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = "https://${module.analysis.cluster_endpoint}"
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = base64decode(module.analysis.cluster_ca_certificate)
  }
}

resource "kubernetes_namespace_v1" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }

  depends_on = [module.analysis]
}

resource "kubernetes_service_account_v1" "jupyter_user" {
  metadata {
    name      = "jupyter-user"
    namespace = kubernetes_namespace_v1.jupyterhub.metadata[0].name

    annotations = {
      "iam.gke.io/gcp-service-account" = module.analysis.jupyter_service_account_email
    }
  }
}

resource "google_service_account_iam_member" "jupyter_workload_identity" {
  service_account_id = module.analysis.jupyter_service_account_name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[jupyterhub/jupyter-user]"
}

resource "helm_release" "jupyterhub" {
  name       = "jupyterhub"
  namespace  = kubernetes_namespace_v1.jupyterhub.metadata[0].name
  repository = "https://hub.jupyter.org/helm-chart/"
  chart      = "jupyterhub"
  version    = var.jupyterhub_chart_version

  values = [
    yamlencode({
      proxy = {
        service = {
          type = "ClusterIP"
        }
      }

      singleuser = {
        serviceAccountName = kubernetes_service_account_v1.jupyter_user.metadata[0].name

        image = {
          name = "quay.io/jupyter/datascience-notebook"
          tag  = "python-3.12"
        }

        cpu = {
          guarantee = 1
        }

        memory = {
          guarantee = "2G"
          limit     = "4G"
        }

        storage = {
          type     = "dynamic"
          capacity = "10Gi"

          dynamic = {
            storageClass = "standard-rwo"
          }
        }

        extraEnv = {
          NOTEBOOK_BUCKET = module.analysis.notebook_bucket
        }
      }
    })
  ]

  depends_on = [
    google_service_account_iam_member.jupyter_workload_identity,
    kubernetes_service_account_v1.jupyter_user,
  ]
}

output "analysis_cluster_name" { value = module.analysis.cluster_name }
output "notebook_bucket" { value = module.analysis.notebook_bucket }
output "portal_uri" { value = module.analysis.portal_uri }
