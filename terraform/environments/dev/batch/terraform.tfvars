project_id             = "dev-com-334508"
region                 = "asia-northeast3"
environment            = "dev"
tf_state_bucket        = "dev-com-334508-managed02-tfstate"

enable_cloud_sql       = false
enable_composer        = true
enable_batch_api       = true

composer_image_version = "composer-3-airflow-2.11.1-build.11"
