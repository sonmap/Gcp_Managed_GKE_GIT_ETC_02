# Gcp_Managed_GKE_GIT_ETC_02

GCP Managed Platform PoC를 **독립 Terraform state** 단위로 분리한 저장소입니다.

## 논리 영역과 Terraform State

| 논리 영역 | Terraform state | 주요 자원 |
|---|---|---|
| 공통 | `common` | APIs, VPC, Subnet |
| 1. 배치 수행 플랫폼 | `batch` | Cloud Composer, Cloud SQL(선택), Cloud Run Batch API |
| 2. L2 모델 수행 환경 | `l2` | L2 전용 GKE Autopilot (`gke-l2-dev`) |
| 3. 모델 배포 환경 | `cicd` | GitHub, Cloud Build SA/Trigger, Artifact Registry |
| 4. 분석과제 수행 환경 | `analysis` | 분석 전용 GKE Autopilot (`gke-analysis-dev`), Cloud Storage, Portal Cloud Run |
| 4. 분석과제 Jupyter | `analysis-jupyterhub` | JupyterHub Helm, Namespace, Workload Identity |

> 분석과제는 GKE 인프라와 Helm/JupyterHub를 기술적으로 2개 state로 나눴습니다. Kubernetes/Helm provider가 이미 생성된 클러스터에 안정적으로 연결되도록 하기 위한 구조입니다.

Secure Source Manager는 사용하지 않고 **GitHub Repository**를 소스 저장소로 사용합니다.

## 디렉터리

```text
cloudbuild/
├── batch.yaml
├── l2.yaml
├── analysis.yaml
└── terraform/
    ├── 10-common-plan.yaml / 11-common-apply.yaml
    ├── 20-cicd-plan.yaml / 21-cicd-apply.yaml
    ├── 30-l2-plan.yaml / 31-l2-apply.yaml
    ├── 40-batch-plan.yaml / 41-batch-apply.yaml
    ├── 50-analysis-plan.yaml / 51-analysis-apply.yaml
    ├── 60-analysis-jupyterhub-plan.yaml / 61-analysis-jupyterhub-apply.yaml
    └── 90-destroy-manual.yaml

terraform/
├── bootstrap/
├── modules/
│   ├── common/
│   ├── batch/
│   ├── l2/
│   ├── cicd/
│   └── analysis/
└── environments/dev/
    ├── common/
    ├── batch/
    ├── l2/
    ├── cicd/
    ├── analysis/
    └── analysis-jupyterhub/
```

## 1. State bucket 생성

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

기본 예제 bucket:

```text
dev-com-334508-managed02-tfstate
```

## 2. 독립 State 초기화/적용

각 디렉터리에서 backend prefix를 다르게 지정합니다.

### Common

```bash
cd terraform/environments/dev/common
terraform init -reconfigure \
  -backend-config="bucket=dev-com-334508-managed02-tfstate" \
  -backend-config="prefix=gcp-managed-02/dev/common"
terraform plan -out=tfplan
terraform apply tfplan
```

### CI/CD

```bash
cd ../cicd
terraform init -reconfigure \
  -backend-config="bucket=dev-com-334508-managed02-tfstate" \
  -backend-config="prefix=gcp-managed-02/dev/cicd"
terraform plan -out=tfplan
terraform apply tfplan
```

### L2 Runtime

```bash
cd ../l2
terraform init -reconfigure \
  -backend-config="bucket=dev-com-334508-managed02-tfstate" \
  -backend-config="prefix=gcp-managed-02/dev/l2"
terraform plan -out=tfplan
terraform apply tfplan
```

### Batch Platform

```bash
cd ../batch
terraform init -reconfigure \
  -backend-config="bucket=dev-com-334508-managed02-tfstate" \
  -backend-config="prefix=gcp-managed-02/dev/batch"
terraform plan -out=tfplan
terraform apply tfplan
```

### Analysis Infrastructure

```bash
cd ../analysis
terraform init -reconfigure \
  -backend-config="bucket=dev-com-334508-managed02-tfstate" \
  -backend-config="prefix=gcp-managed-02/dev/analysis"
terraform plan -out=tfplan
terraform apply tfplan
```

### JupyterHub

```bash
cd ../analysis-jupyterhub
terraform init -reconfigure \
  -backend-config="bucket=dev-com-334508-managed02-tfstate" \
  -backend-config="prefix=gcp-managed-02/dev/analysis-jupyterhub"
terraform plan -out=tfplan
terraform apply tfplan
```

## 적용 순서

```text
bootstrap
   ↓
common
   ├──→ cicd
   ├──→ l2
   ├──→ batch
   └──→ analysis
            ↓
       analysis-jupyterhub
```

Cloud Composer가 L2 GKE를 호출하는 런타임 관계는 있지만 `batch`와 `l2` Terraform state는 서로 독립입니다.

## GitHub Trigger

`terraform/environments/dev/cicd/terraform.tfvars`의 기본값은:

```hcl
enable_github_triggers = false
```

입니다. 먼저 Google Cloud Build에서 이 GitHub repository를 연결한 후 `true`로 변경하세요.

## Terraform Cloud Build 자동화

VM에서 직접 수행하던 Terraform 작업을 stage별 Cloud Build YAML로 분리했습니다.

```text
Pull Request
   ↓
Stage별 terraform plan
   ↓
Review / 승인
   ↓
main merge
   ↓
Stage별 terraform apply
   ↓
GCS Remote State
```

Stage는 `common`, `cicd`, `l2`, `batch`, `analysis`, `analysis-jupyterhub`로 분리되어 있으며 각 state에 대해 Plan/Apply YAML이 별도로 있습니다.

Destroy는 자동 trigger에 연결하지 않고 `cloudbuild/terraform/90-destroy-manual.yaml`을 통한 명시적 수동 실행만 허용하도록 구성했습니다.

본 시스템의 내부망 운영에서는 Cloud Build Private Pool과 내부 Artifact Registry의 Terraform runner image를 사용하도록 전환합니다.

세부 사용법과 Trigger 권장 매핑은 [`cloudbuild/terraform/README.md`](cloudbuild/terraform/README.md)를 참고하세요.

자세한 전체 아키텍처는 `docs/ARCHITECTURE.md`를 참고하세요.
