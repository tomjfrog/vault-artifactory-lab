#!/usr/bin/env bash
# Phase 3: Install External Secrets Operator and apply VaultDynamicSecret + ExternalSecret.
# Prerequisites: Phase 1 (setup-phase1-vault.sh) and Phase 2 (setup-kubernetes-auth.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ESO_DIR="${LAB_ROOT}/k8s/eso"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_TOKEN:=root}"
: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${ASK123_VAULT_ROLE:=ask123}"
: "${K8S_NAMESPACE:=ask123-ns}"
: "${K8S_WORKLOAD_SA:=workload-sa}"
: "${K8S_AUTH_ROLE:=ask123-workload}"
: "${VAULT_K8S_AUTH_PATH:=kubernetes}"
: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_REGISTRY:=${JFROG_URL#https://}}"
: "${VAULT_URL_FOR_CLUSTER:=http://host.docker.internal:8200}"
: "${ESO_NAMESPACE:=external-secrets}"
: "${ESO_RELEASE:=external-secrets}"
: "${ESO_CHART:=external-secrets/external-secrets}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd helm
require_cmd kubectl
require_cmd envsubst
require_cmd vault

export VAULT_ADDR VAULT_TOKEN

echo "==> Verify Vault and artifactory plugin"
if ! vault read "${PLUGIN_VAULT_PATH}/token/${ASK123_VAULT_ROLE}" >/dev/null 2>&1; then
  echo "ERROR: cannot read ${PLUGIN_VAULT_PATH}/token/${ASK123_VAULT_ROLE}" >&2
  echo "  Is Vault running? Is plugin admin config valid (token not revoked)?" >&2
  exit 1
fi

echo "==> Ensure workload namespace and service account exist"
kubectl create namespace "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "${K8S_WORKLOAD_SA}" -n "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Install External Secrets Operator (if missing)"
if ! helm status "${ESO_RELEASE}" -n "${ESO_NAMESPACE}" >/dev/null 2>&1; then
  helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
  helm repo update external-secrets
  helm install "${ESO_RELEASE}" "${ESO_CHART}" \
    -n "${ESO_NAMESPACE}" \
    --create-namespace \
    --set installCRDs=true \
    --wait \
    --timeout 5m
else
  echo "  release ${ESO_RELEASE} already installed in ${ESO_NAMESPACE}"
fi

kubectl wait --for=condition=Available deployment/external-secrets -n "${ESO_NAMESPACE}" --timeout=120s
kubectl wait --for=condition=Available deployment/external-secrets-webhook -n "${ESO_NAMESPACE}" --timeout=120s 2>/dev/null || true

echo ""
echo "==> Remove manual pull secret if present (ESO will own artifactory-pull)"
kubectl delete secret artifactory-pull -n "${K8S_NAMESPACE}" --ignore-not-found

echo ""
echo "==> Apply VaultDynamicSecret and ExternalSecret"
export K8S_NAMESPACE K8S_WORKLOAD_SA K8S_AUTH_ROLE VAULT_K8S_AUTH_PATH \
  PLUGIN_VAULT_PATH ASK123_VAULT_ROLE JFROG_REGISTRY VAULT_URL_FOR_CLUSTER

envsubst < "${ESO_DIR}/vault-dynamic-secret.yaml" | kubectl apply -f -
envsubst < "${ESO_DIR}/external-secret.yaml" | kubectl apply -f -

echo ""
echo "Phase 3 ESO resources applied."
echo "  Vault URL (from cluster): ${VAULT_URL_FOR_CLUSTER}"
echo "  Validate: ./scripts/demo-eso.sh"
