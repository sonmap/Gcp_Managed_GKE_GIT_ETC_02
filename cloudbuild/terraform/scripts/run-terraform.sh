#!/bin/sh
set -eu

ACTION="${ACTION:-plan}"
STAGE="${STAGE:-}"
TF_ENV="${TF_ENV:-dev}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_PREFIX_ROOT="${TF_STATE_PREFIX_ROOT:-gcp-managed-02}"
TF_VAR_FILE="${TF_VAR_FILE:-terraform.tfvars}"
TF_LOCK_TIMEOUT="${TF_LOCK_TIMEOUT:-5m}"
ALLOW_DESTROY="${ALLOW_DESTROY:-false}"

case "${STAGE}" in
  common|cicd|l2|batch|analysis|analysis-jupyterhub) ;;
  *)
    echo "ERROR: unsupported STAGE='${STAGE}'"
    echo "Allowed: common, cicd, l2, batch, analysis, analysis-jupyterhub"
    exit 2
    ;;
esac

if [ -z "${TF_STATE_BUCKET}" ]; then
  echo "ERROR: TF_STATE_BUCKET is required"
  exit 2
fi

TF_DIR="terraform/environments/${TF_ENV}/${STAGE}"
STATE_PREFIX="${TF_STATE_PREFIX_ROOT}/${TF_ENV}/${STAGE}"
PLAN_FILE="/workspace/tfplan-${STAGE}"

if [ ! -d "${TF_DIR}" ]; then
  echo "ERROR: Terraform directory not found: ${TF_DIR}"
  exit 2
fi

cd "${TF_DIR}"

echo "============================================================"
echo "Terraform Cloud Build"
echo "ACTION       : ${ACTION}"
echo "STAGE        : ${STAGE}"
echo "ENV          : ${TF_ENV}"
echo "STATE BUCKET : ${TF_STATE_BUCKET}"
echo "STATE PREFIX : ${STATE_PREFIX}"
echo "============================================================"

terraform version
terraform fmt -check

terraform init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="prefix=${STATE_PREFIX}"

terraform validate

case "${ACTION}" in
  plan)
    terraform plan \
      -input=false \
      -lock-timeout="${TF_LOCK_TIMEOUT}" \
      -var-file="${TF_VAR_FILE}"
    ;;

  apply)
    terraform plan \
      -input=false \
      -lock-timeout="${TF_LOCK_TIMEOUT}" \
      -var-file="${TF_VAR_FILE}" \
      -out="${PLAN_FILE}"

    terraform apply \
      -input=false \
      "${PLAN_FILE}"
    ;;

  destroy)
    if [ "${ALLOW_DESTROY}" != "true" ]; then
      echo "ERROR: destroy is protected. Set ALLOW_DESTROY=true explicitly."
      exit 3
    fi

    terraform plan \
      -destroy \
      -input=false \
      -lock-timeout="${TF_LOCK_TIMEOUT}" \
      -var-file="${TF_VAR_FILE}" \
      -out="${PLAN_FILE}"

    terraform apply \
      -input=false \
      "${PLAN_FILE}"
    ;;

  *)
    echo "ERROR: unsupported ACTION='${ACTION}' (plan|apply|destroy)"
    exit 2
    ;;
esac
