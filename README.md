# Gcp_Managed_GKE_GIT_ETC_02

GCP Managed Platform PoC를 **독립 Terraform state** 단위로 분리한 예제 저장소입니다.

## 아키텍처 영역

1. `common` - 공통 VPC/Subnet/API/Terraform 기반
2. `batch` - Cloud Composer / Cloud SQL / Batch API 기반
3. `l2` - L2 모델 실행 전용 GKE Autopilot
4. `cicd` - GitHub + Cloud Build + Artifact Registry + Build Service Accounts
5. `analysis` - 분석과제 전용 GKE Autopilot + JupyterHub 기반 + Cloud Storage

> Secure Source Manager는 PoC 비용을 고려해 사용하지 않고 GitHub를 소스 저장소로 사용합니다.

각 영역은 별도의 GCS backend prefix를 사용하므로 독립적으로 `plan/apply/destroy`할 수 있습니다.
