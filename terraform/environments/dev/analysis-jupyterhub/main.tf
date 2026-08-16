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

data "terraform_remote_state" "analysis" {
  backend = "gcs"

  config = {
    bucket = var.tf_state_bucket
    prefix = "gcp-managed-02/${var.environment}/analysis"
  }
}

data "google_client_config" "current" {}

provider "kubernetes" {
  host                   = "https://${data.terraform_remote_state.analysis.outputs.analysis_cluster_endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.analysis.outputs.analysis_cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = "https://${data.terraform_remote_state.analysis.outputs.analysis_cluster_endpoint}"
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = base64decode(data.terraform_remote_state.analysis.outputs.analysis_cluster_ca_certificate)
  }
}

resource "kubernetes_namespace_v1" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}

resource "kubernetes_service_account_v1" "jupyter_user" {
  metadata {
    name      = "jupyter-user"
    namespace = kubernetes_namespace_v1.jupyterhub.metadata[0].name

    annotations = {
      "iam.gke.io/gcp-service-account" = data.terraform_remote_state.analysis.outputs.jupyter_service_account_email
    }
  }
}

resource "google_service_account_iam_member" "jupyter_workload_identity" {
  service_account_id = data.terraform_remote_state.analysis.outputs.jupyter_service_account_name
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
          NOTEBOOK_BUCKET = data.terraform_remote_state.analysis.outputs.notebook_bucket
        }
      }
    })
  ]

  depends_on = [
    google_service_account_iam_member.jupyter_workload_identity,
    kubernetes_service_account_v1.jupyter_user,
  ]
}

output "jupyterhub_namespace" {
  value = kubernetes_namespace_v1.jupyterhub.metadata[0].name
}
