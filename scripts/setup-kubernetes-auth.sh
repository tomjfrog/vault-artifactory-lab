#!/usr/bin/env bash
# Phase 2: Vault Kubernetes auth for workload SA → policy vaultdemo-ask123-pull.
# Prerequisites: Phase 1 complete (setup-phase1-vault.sh), kubectl cluster reachable,
# Vault dev server running on host (Rancher Desktop k3s at 127.0.0.1:6443).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${K8S_NAMESPACE:=vaultdemo-ns}"
: "${K8S_WORKLOAD_SA:=workload-sa}"
: "${K8S_AUTH_ROLE:=vaultdemo-workload}"
: "${VAULT_K8S_AUTH_PATH:=kubernetes}"
: "${K8S_VAULT_AUTH_SA:=vault-auth}"
: "${K8S_VAULT_AUTH_NS:=kube-system}"
: "${K8S_VAULT_AUTH_BINDING:=vault-auth-delegator}"
: "${K8S_REVIEWER_TOKEN_DURATION:=87600h}"

export VAULT_ADDR VAULT_TOKEN

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd vault
require_cmd jq

echo "==> Kubernetes cluster"
kubectl cluster-info
KUBE_HOST="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')"
KUBE_CA_CERT="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)"
echo "  API server: ${KUBE_HOST}"

echo ""
echo "==> Workload namespace and service account"
kubectl create namespace "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "${K8S_WORKLOAD_SA}" -n "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "  namespace: ${K8S_NAMESPACE}"
echo "  service account: ${K8S_WORKLOAD_SA}"

echo ""
echo "==> Vault token reviewer service account (kube-system)"
kubectl create serviceaccount "${K8S_VAULT_AUTH_SA}" -n "${K8S_VAULT_AUTH_NS}" --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl get clusterrolebinding "${K8S_VAULT_AUTH_BINDING}" >/dev/null 2>&1; then
  kubectl create clusterrolebinding "${K8S_VAULT_AUTH_BINDING}" \
    --clusterrole=system:auth-delegator \
    --serviceaccount="${K8S_VAULT_AUTH_NS}:${K8S_VAULT_AUTH_SA}"
fi
REVIEWER_JWT="$(kubectl create token "${K8S_VAULT_AUTH_SA}" -n "${K8S_VAULT_AUTH_NS}" --duration="${K8S_REVIEWER_TOKEN_DURATION}")"
echo "  reviewer SA: ${K8S_VAULT_AUTH_NS}/${K8S_VAULT_AUTH_SA}"

echo ""
echo "==> Enable Vault Kubernetes auth"
if ! vault auth list -format=json | jq -e --arg p "${VAULT_K8S_AUTH_PATH}/" '.[ $p ]' >/dev/null; then
  vault auth enable -path="${VAULT_K8S_AUTH_PATH}" kubernetes
else
  echo "  already enabled at auth/${VAULT_K8S_AUTH_PATH}"
fi

echo "==> Configure auth/${VAULT_K8S_AUTH_PATH}/config"
vault write "auth/${VAULT_K8S_AUTH_PATH}/config" \
  kubernetes_host="${KUBE_HOST}" \
  kubernetes_ca_cert="${KUBE_CA_CERT}" \
  token_reviewer_jwt="${REVIEWER_JWT}"

echo ""
echo "==> Create Kubernetes auth role ${K8S_AUTH_ROLE}"
vault write "auth/${VAULT_K8S_AUTH_PATH}/role/${K8S_AUTH_ROLE}" \
  bound_service_account_names="${K8S_WORKLOAD_SA}" \
  bound_service_account_namespaces="${K8S_NAMESPACE}" \
  policies="vaultdemo-ask123-pull" \
  ttl=1h \
  max_ttl=3h

vault read "auth/${VAULT_K8S_AUTH_PATH}/role/${K8S_AUTH_ROLE}"

echo ""
echo "Phase 2 Kubernetes auth configured."
echo "  Validate: ./scripts/demo-kubernetes-auth.sh"
