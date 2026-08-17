# Terraform Cloud Build 자동화

기존 VM(`son01`)에서 직접 실행하던 Terraform을 **GitHub → Cloud Build → Terraform → GCS State** 흐름으로 전환하기 위한 구성입니다.

## 기본 정책

- Terraform state는 기존 독립 state 구조를 그대로 유지합니다.
- PR에서는 `plan`만 수행합니다.
- `main` merge 후에는 stage별 `apply`를 수행합니다.
- `destroy`는 GitHub push trigger에 연결하지 않고 수동 실행만 허용합니다.
- 운영 내부망에서는 Cloud Build **Private Pool + no public egress**를 사용합니다.
- 운영 내부망에서는 Terraform 실행 이미지도 Artifact Registry `build-tools`에 사전 반입합니다.

## 파일 구조

```text
cloudbuild/terraform/
├── 00-build-terraform-runner.yaml
├── 10-common-plan.yaml
├── 11-common-apply.yaml
├── 20-cicd-plan.yaml
├── 21-cicd-apply.yaml
├── 30-l2-plan.yaml
├── 31-l2-apply.yaml
├── 40-batch-plan.yaml
├── 41-batch-apply.yaml
├── 50-analysis-plan.yaml
├── 51-analysis-apply.yaml
├── 60-analysis-jupyterhub-plan.yaml
├── 61-analysis-jupyterhub-apply.yaml
├── 90-destroy-manual.yaml
├── runner/
│   └── Dockerfile
└── scripts/
    └── run-terraform.sh
```

## Stage / State 매핑

| 순서 | Stage | Terraform 경로 | GCS backend prefix | Plan YAML | Apply YAML |
|---|---|---|---|---|---|
| 1 | common | `terraform/environments/dev/common` | `gcp-managed-02/dev/common` | `10-common-plan.yaml` | `11-common-apply.yaml` |
| 2 | cicd | `terraform/environments/dev/cicd` | `gcp-managed-02/dev/cicd` | `20-cicd-plan.yaml` | `21-cicd-apply.yaml` |
| 3 | l2 | `terraform/environments/dev/l2` | `gcp-managed-02/dev/l2` | `30-l2-plan.yaml` | `31-l2-apply.yaml` |
| 4 | batch | `terraform/environments/dev/batch` | `gcp-managed-02/dev/batch` | `40-batch-plan.yaml` | `41-batch-apply.yaml` |
| 5 | analysis | `terraform/environments/dev/analysis` | `gcp-managed-02/dev/analysis` | `50-analysis-plan.yaml` | `51-analysis-apply.yaml` |
| 6 | analysis-jupyterhub | `terraform/environments/dev/analysis-jupyterhub` | `gcp-managed-02/dev/analysis-jupyterhub` | `60-analysis-jupyterhub-plan.yaml` | `61-analysis-jupyterhub-apply.yaml` |

적용 의존 순서는 다음과 같습니다.

```text
common
  ├─ cicd
  ├─ l2
  ├─ batch
  └─ analysis
       └─ analysis-jupyterhub
```

전체 재구축 시에는 안전하게 아래 순서로 실행합니다.

```text
common → cicd → l2 → batch → analysis → analysis-jupyterhub
```

삭제는 역순을 사용합니다.

## 공통 실행 스크립트

각 YAML은 `scripts/run-terraform.sh`를 호출합니다. 스크립트는 다음을 공통 수행합니다.

```text
terraform version
terraform fmt -check
terraform init -reconfigure (GCS backend)
terraform validate
terraform plan
[apply이면] terraform apply saved-plan
```

State lock 대기시간은 기본 `5m`입니다.

## PR / main Trigger 권장 매핑

| Stage | PR Trigger | main Push Trigger | Included files 권장 |
|---|---|---|---|
| common | `tf-common-plan` | `tf-common-apply` | `terraform/modules/common/**`, `terraform/environments/dev/common/**` |
| cicd | `tf-cicd-plan` | `tf-cicd-apply` | `terraform/modules/cicd/**`, `terraform/environments/dev/cicd/**` |
| l2 | `tf-l2-plan` | `tf-l2-apply` | `terraform/modules/l2/**`, `terraform/environments/dev/l2/**` |
| batch | `tf-batch-plan` | `tf-batch-apply` | `terraform/modules/batch/**`, `terraform/environments/dev/batch/**` |
| analysis | `tf-analysis-plan` | `tf-analysis-apply` | `terraform/modules/analysis/**`, `terraform/environments/dev/analysis/**` |
| analysis-jupyterhub | `tf-analysis-jupyterhub-plan` | `tf-analysis-jupyterhub-apply` | `terraform/environments/dev/analysis-jupyterhub/**` |

`cloudbuild/terraform/**` 변경 시에는 관련 trigger를 함께 실행하도록 included files에 해당 YAML 경로도 추가하는 것을 권장합니다.

## 테스트 환경에서 수동 실행

예: common plan

```bash
gcloud builds submit \
  --project=dev-com-334508 \
  --region=asia-northeast3 \
  --config=cloudbuild/terraform/10-common-plan.yaml \
  .
```

예: common apply

```bash
gcloud builds submit \
  --project=dev-com-334508 \
  --region=asia-northeast3 \
  --config=cloudbuild/terraform/11-common-apply.yaml \
  .
```

## Destroy 보호

`90-destroy-manual.yaml`은 기본적으로 실행이 차단됩니다.

```yaml
_TF_STAGE: DO_NOT_RUN
_ALLOW_DESTROY: 'false'
```

명시적으로 stage와 허용 플래그를 넘겨야 합니다.

```bash
gcloud builds submit \
  --project=dev-com-334508 \
  --region=asia-northeast3 \
  --config=cloudbuild/terraform/90-destroy-manual.yaml \
  --substitutions=_TF_STAGE=analysis-jupyterhub,_ALLOW_DESTROY=true \
  .
```

운영에서는 Destroy trigger를 만들지 않는 것을 원칙으로 합니다.

## Terraform Runner Image

YAML 기본값은 PoC 편의를 위해 다음 public image를 사용합니다.

```text
hashicorp/terraform:1.13.3
```

본 시스템은 외부 인터넷 egress를 사용하지 않으므로 운영 전환 전에 내부 Artifact Registry 이미지로 변경합니다.

```text
asia-northeast3-docker.pkg.dev/<PROJECT_ID>/build-tools/terraform-runner:1.13.3
```

`00-build-terraform-runner.yaml`은 테스트/전환 시 Terraform runner image를 `build-tools` repository에 생성하는 용도입니다. 운영망에서 public base image 접근을 차단한 이후에는 외부에서 직접 빌드하지 말고 승인된 이미지 반입 절차를 사용합니다.

각 stage YAML의 `_TERRAFORM_IMAGE` substitution을 내부 이미지로 변경하거나 Trigger substitution에서 override할 수 있습니다.

## 내부망 운영

운영에서는 Cloud Build Private Pool을 사용하고 public egress를 차단합니다.

```text
GitHub / 승인된 Source
       ↓
Cloud Build Trigger
       ↓
Private Pool (no public egress)
       ↓
Private VPC
       ├─ GCS Terraform State
       ├─ Artifact Registry
       ├─ Private GKE
       ├─ Cloud SQL
       └─ Google APIs (Private Google Access/PSC 정책)
```

Private GKE control plane 접근은 실제 본 시스템 네트워크 설계에 맞춰 별도 검증해야 합니다. Private Pool과 GKE control plane의 네트워크 경로는 단순 VPC peering만으로 해결되지 않는 구성도 있으므로 사전 통신 설계가 필요합니다.

## 권한 원칙

Cloud Build Terraform Service Account는 stage별로 분리하는 것을 권장합니다.

```text
cb-tf-common-dev-02
cb-tf-cicd-dev-02
cb-tf-l2-dev-02
cb-tf-batch-dev-02
cb-tf-analysis-dev-02
cb-tf-jupyter-dev-02
```

각 계정에는 해당 stage가 실제 생성/변경하는 GCP 리소스 권한과 Terraform State Bucket 접근 권한만 부여합니다. `Owner` / `Editor` 프로젝트 전역 권한은 사용하지 않는 것을 원칙으로 합니다.
