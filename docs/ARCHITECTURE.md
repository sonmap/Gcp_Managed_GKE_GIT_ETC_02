# 독립 Terraform 아키텍처

## 설계 원칙

기존 단일 Terraform root를 논리 영역별로 분리하고, 각 영역은 별도의 GCS backend prefix를 사용합니다.

| 영역 | State | 설명 |
|---|---|---|
| 공통 | `common` | API, VPC, Subnet |
| 1. 배치 수행 플랫폼 | `batch` | Composer, Cloud SQL(선택), Batch API Cloud Run |
| 2. L2 모델 수행 환경 | `l2` | L2 전용 GKE Autopilot |
| 3. 모델 배포 환경 | `cicd` | GitHub + Cloud Build + Artifact Registry |
| 4. 분석과제 인프라 | `analysis` | 분석 전용 GKE Autopilot + GCS + Portal Cloud Run |
| 4. JupyterHub | `analysis-jupyterhub` | Helm/JupyterHub + Workload Identity |

분석과제는 하나의 논리 영역이지만 **GKE 생성 state와 Helm/JupyterHub state를 분리**합니다. Kubernetes/Helm provider는 이미 존재하는 클러스터 endpoint를 사용하는 편이 안정적이기 때문입니다.

## 전체 흐름

```text
GitHub: sonmap/Gcp_Managed_GKE_GIT_ETC_02
                 |
                 v
      [3. 모델 배포 / CI-CD]
      Cloud Build + Artifact Registry
             |                |
             v                v
 [1. Batch Platform]   [2. L2 Runtime]
 Composer -----------> GKE Autopilot
 Cloud Run             gke-l2-dev

 [4. Analysis Platform]
 User -> Portal -> Cloud Run
                    |
                    v
             GKE Autopilot
             gke-analysis-dev
                    |
                JupyterHub
                    |
             User Jupyter Pods
                    |
              Cloud Storage
```

L2용 `gke-l2-dev`와 분석용 `gke-analysis-dev`는 별도 클러스터입니다.

## State Layout

```text
gs://<TF_STATE_BUCKET>/
  gcp-managed-02/dev/common/
  gcp-managed-02/dev/batch/
  gcp-managed-02/dev/l2/
  gcp-managed-02/dev/cicd/
  gcp-managed-02/dev/analysis/
  gcp-managed-02/dev/analysis-jupyterhub/
```

따라서 `terraform destroy`를 수행하더라도 해당 state의 자원만 대상으로 합니다. 단, remote state 의존성 때문에 `common`은 가장 마지막에 삭제해야 합니다.

## 적용 순서

1. `terraform/bootstrap`
2. `terraform/environments/dev/common`
3. `terraform/environments/dev/cicd`
4. `terraform/environments/dev/l2`
5. `terraform/environments/dev/batch`
6. `terraform/environments/dev/analysis`
7. `terraform/environments/dev/analysis-jupyterhub`

삭제는 역순을 권장합니다.

## GitHub / Cloud Build

Secure Source Manager는 PoC에서 사용하지 않습니다. GitHub를 Source of Truth로 사용합니다.

`cicd` module은 다음을 관리합니다.

- `app-images`
- `model-images`
- `notebook-images`
- `python-packages`
- `cb-batch-dev-02`
- `cb-l2-dev-02`
- `cb-analysis-dev-02`
- 선택적 GitHub Cloud Build Trigger

GitHub Trigger는 기본적으로 비활성화되어 있습니다. GCP Cloud Build의 GitHub App 연결이 완료된 뒤 활성화합니다.

## 1. Batch Platform

기본값:

- Composer: enabled
- Batch API Cloud Run: enabled
- Cloud SQL: disabled (비용 절감)

Composer SA에는 `roles/composer.worker`와 L2 GKE Pod 실행을 위한 `roles/container.developer`를 부여합니다.

## 2. L2 Runtime

- Cluster: `gke-l2-dev`
- GKE Autopilot
- Private nodes
- Public control-plane endpoint
- Dedicated node SA
- Artifact Registry read 권한

Composer DAG에서 `GKEStartPodOperator`로 이 클러스터를 호출하는 구조를 전제로 합니다.

## 3. Model Deployment

GitHub push를 시작점으로 Cloud Build가 Artifact Registry에 이미지를 저장하고 각 런타임으로 배포하는 구조입니다.

Cloud Build YAML은 Terraform 내부에 넣지 않고 repository의 `cloudbuild/` 디렉터리에서 버전 관리합니다.

## 4. Analysis Platform

### analysis state

- Cluster: `gke-analysis-dev`
- GKE Autopilot
- Notebook GCS bucket
- Jupyter GSA
- Portal Cloud Run skeleton

### analysis-jupyterhub state

- `jupyterhub` namespace
- `jupyter-user` Kubernetes ServiceAccount
- GSA/KSA Workload Identity
- JupyterHub Helm release
- 사용자별 10Gi dynamic PVC
- Notebook bucket 환경변수

Portal Cloud Run과 JupyterHub의 실제 Workspace API 연동은 별도 애플리케이션 코드 영역입니다.
