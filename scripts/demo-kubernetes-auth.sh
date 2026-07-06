#!/usr/bin/env bash
# Phase 2 validation: workload SA JWT → Vault Kubernetes auth → artifactory/token/vaultdemo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${DEMO_ROLE:=vaultdemo}"
: "${K8S_NAMESPACE:=vaultdemo-ns}"
: "${K8S_WORKLOAD_SA:=workload-sa}"
: "${K8S_AUTH_ROLE:=vaultdemo-workload}"
: "${VAULT_K8S_AUTH_PATH:=kubernetes}"
: "${K8S_WORKLOAD_TOKEN_DURATION:=1h}"

export VAULT_ADDR

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd vault
require_cmd jq

echo "==> Mint service account JWT (${K8S_NAMESPACE}/${K8S_WORKLOAD_SA})"
SA_JWT="$(kubectl create token "${K8S_WORKLOAD_SA}" -n "${K8S_NAMESPACE}" --duration="${K8S_WORKLOAD_TOKEN_DURATION}")"
[[ -n "${SA_JWT}" ]] && pass "SA JWT issued"

echo ""
echo "==> Login to Vault via Kubernetes auth (role ${K8S_AUTH_ROLE})"
LOGIN_RESP="$(vault write -format=json "auth/${VAULT_K8S_AUTH_PATH}/login" role="${K8S_AUTH_ROLE}" jwt="${SA_JWT}")"
WORKLOAD_VAULT_TOKEN="$(echo "${LOGIN_RESP}" | jq -r '.auth.client_token')"
WORKLOAD_POLICIES="$(echo "${LOGIN_RESP}" | jq -r '.auth.policies | join(",")')"
[[ -n "${WORKLOAD_VAULT_TOKEN}" && "${WORKLOAD_VAULT_TOKEN}" != "null" ]] \
  && pass "Vault login succeeded (policies: ${WORKLOAD_POLICIES})" \
  || fail "Vault Kubernetes login failed"

echo "${WORKLOAD_POLICIES}" | grep -q "vaultdemo-ask123-pull" \
  && pass "policy vaultdemo-ask123-pull attached" \
  || fail "expected policy vaultdemo-ask123-pull not on token"

echo ""
echo "==> Read Artifactory token using workload Vault token (no root token)"
ARTIFACTORY_RESP="$(VAULT_TOKEN="${WORKLOAD_VAULT_TOKEN}" vault read -format=json "${PLUGIN_VAULT_PATH}/token/${DEMO_ROLE}")"
TOKEN_SCOPE="$(echo "${ARTIFACTORY_RESP}" | jq -r '.data.scope')"
TOKEN_USERNAME="$(echo "${ARTIFACTORY_RESP}" | jq -r '.data.username')"
ACCESS_TOKEN="$(echo "${ARTIFACTORY_RESP}" | jq -r '.data.access_token')"

echo "  username: ${TOKEN_USERNAME}"
echo "  scope:    ${TOKEN_SCOPE}"

[[ "${TOKEN_SCOPE}" == *"AZU_ARTIFACTORY_ASK123"* ]] \
  && pass "Artifactory token scope includes AZU_ARTIFACTORY_ASK123" \
  || fail "unexpected scope: ${TOKEN_SCOPE}"

[[ -n "${ACCESS_TOKEN}" && "${ACCESS_TOKEN}" != "null" ]] \
  && pass "access_token issued" \
  || fail "no access_token returned"

echo ""
echo "==> Negative test: workload token cannot read root-only paths"
if VAULT_TOKEN="${WORKLOAD_VAULT_TOKEN}" vault read artifactory/config/admin >/dev/null 2>&1; then
  fail "workload token should not read artifactory/config/admin"
else
  pass "artifactory/config/admin denied for workload token"
fi

echo ""
echo "Phase 2 Kubernetes auth validation complete."
