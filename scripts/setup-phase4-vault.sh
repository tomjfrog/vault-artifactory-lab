#!/usr/bin/env bash
# Phase 4: Vault role/policy + Kubernetes auth for app ASK456.
# Prerequisites: Phase 4 Artifactory (setup-phase4-artifactory.sh), Phase 2 K8s auth enabled.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${ASK456_ID:=ASK456}"
: "${ASK456_GROUP:=AZU_ARTIFACTORY_${ASK456_ID}}"
: "${ASK456_ROLE:=vaultdemo-ask456}"
: "${ASK456_POLICY:=vaultdemo-ask456-pull}"
: "${ASK456_NAMESPACE:=vaultdemo-ask456-ns}"
: "${ASK456_WORKLOAD_SA:=workload-sa}"
: "${ASK456_K8S_AUTH_ROLE:=vaultdemo-ask456-workload}"
: "${VAULT_K8S_AUTH_PATH:=kubernetes}"

ASK456_SCOPE="applied-permissions/groups:${ASK456_GROUP}"

export VAULT_ADDR VAULT_TOKEN

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd vault
require_cmd kubectl

if ! vault auth list -format=json | jq -e --arg p "${VAULT_K8S_AUTH_PATH}/" '.[ $p ]' >/dev/null; then
  echo "ERROR: auth/${VAULT_K8S_AUTH_PATH} not enabled — run ./scripts/setup-kubernetes-auth.sh first" >&2
  exit 1
fi

echo "==> Writing Vault policy ${ASK456_POLICY}"
vault policy write "${ASK456_POLICY}" "${LAB_ROOT}/policies/${ASK456_POLICY}.hcl"

echo "==> Writing plugin role ${ASK456_ROLE} (scope: ${ASK456_SCOPE})"
vault write "${PLUGIN_VAULT_PATH}/roles/${ASK456_ROLE}" \
  scope="${ASK456_SCOPE}" \
  default_ttl=1h max_ttl=3h

vault read "${PLUGIN_VAULT_PATH}/roles/${ASK456_ROLE}"

echo ""
echo "==> Kubernetes namespace and service account (${ASK456_NAMESPACE})"
kubectl create namespace "${ASK456_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "${ASK456_WORKLOAD_SA}" -n "${ASK456_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Kubernetes auth role ${ASK456_K8S_AUTH_ROLE}"
vault write "auth/${VAULT_K8S_AUTH_PATH}/role/${ASK456_K8S_AUTH_ROLE}" \
  bound_service_account_names="${ASK456_WORKLOAD_SA}" \
  bound_service_account_namespaces="${ASK456_NAMESPACE}" \
  policies="${ASK456_POLICY}" \
  ttl=1h \
  max_ttl=3h

vault read "auth/${VAULT_K8S_AUTH_PATH}/role/${ASK456_K8S_AUTH_ROLE}"

echo ""
echo "Phase 4 Vault configuration complete."
echo "  Validate: ./scripts/demo-isolation-multi-app.sh"
