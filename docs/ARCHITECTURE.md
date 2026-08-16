# 독립 Terraform 아키텍처

## 목적

기존 단일 Terraform root를 다음 5개 독립 state로 분리합니다.

| State | 목적 | 주요 자원 |
|---|---|---|
| `common` | 공통 기반 | APIs, VPC, Subnet |
| `batch` | 1. 배치 수행 플랫폼 | Cloud Composer, Cloud SQL(선택), Cloud Run Batch API |
| `l2` | 2. L2 모델 수행 환경 | 전용 GKE Autopilot |
| `cicd` | 3. 모델 배포 환경 | GitHub Trigger(선택), Cloud Build SA, Artifact Registry |
| `analysis` | 4. 분석과제 수행 환경 | 전용 GKE Autopilot, JupyterHub, Cloud Storage, Portal Cloud Run |

## 흐름

```text
GitHub: sonmap/Gcp_Managed_GKE_GIT_ETC_02
                 |
                 v
        [3. CI/CD / 모델 배포]
        Cloud Build + Artifact Registry
             |              |
             v              v
 [1. Batch Platform]   [2. L2 Runtime]
 Composer/Cloud Run --> GKE Autopilot (gke-l2-dev)

 [4. Analysis Platform]
 User/Portal -> Cloud Run -> GKE Autopilot (gke-analysis-dev)
                              |
                           JupyterHub
                              |
                         Cloud Storage
```

L2용 GKE와 분석용 GKE는 **물리적으로 별도 클러스터**입니다.

## Terraform State

동일한 GCS bucket을 사용하되 prefix를 분리합니다.

```text
gs://<TF_STATE_BUCKET>/
  gcp-managed-02/dev/common/
  gcp-managed-02/dev/batch/
  gcp-managed-02/dev/l2/
  gcp-managed-02/dev/cicd/
  gcp-managed-02/dev/analysis/
```

따라서 특정 영역만 독립적으로 `plan/apply/destroy`할 수 있습니다.

## 적용 순서

1. `terraform/bootstrap`
2. `terraform/environments/dev/common`
3. `terraform/environments/dev/cicd`
4. `terraform/environments/dev/l2`
5. `terraform/environments/dev/batch`
6. `terraform/environments/dev/analysis`

`batch`와 `l2`는 런타임 관계(Composer -> GKE)가 있지만 Terraform state는 분리합니다.

## GitHub / Cloud Build

Secure Source Manager는 사용하지 않습니다. GitHub Repository를 사용합니다.

`cicd`의 GitHub Trigger는 기본값이 `false`입니다. GCP Cloud Build에서 GitHub App 연결을 먼저 완료한 후 `enable_github_triggers = true`로 변경합니다.

## 분석 플랫폼 주의사항

`analysis` state는 JupyterHub를 Helm으로 설치합니다. 초기 PoC는 다음 범위입니다.

- `gke-analysis-dev` 전용 Autopilot
- `jupyterhub` namespace
- 사용자 Jupyter Pod
- Notebook용 Cloud Storage bucket
- Jupyter GSA/KSA Workload Identity 연결
- Portal Cloud Run 골격

Portal Cloud Run과 JupyterHub API의 실제 애플리케이션 연계는 Portal 애플리케이션 코드에서 구현합니다.
