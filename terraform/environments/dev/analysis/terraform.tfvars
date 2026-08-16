project_id                    = "dev-com-334508"
region                        = "asia-northeast3"
environment                   = "dev"
tf_state_bucket               = "dev-com-334508-managed02-tfstate"

# 운영에서는 반드시 특정 chart version을 고정 권장
jupyterhub_chart_version      = null

force_destroy_notebook_bucket = false
