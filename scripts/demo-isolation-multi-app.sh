#!/usr/bin/env bash
# Phase 4: cross-app isolation — ASK123 (project ask123) vs ASK456 (project ask456).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_REGISTRY:=${JFROG_URL#https://}}"
: "${DOCKER_TAG:=1.0.0}"

# ASK123 (JFrog project ask123)
: "${ASK123_VAULT_ROLE:=ask123}"
: "${ASK123_VAULT_POLICY:=ask123-pull}"
: "${ASK123_GROUP:=AZU_ARTIFACTORY_ASK123}"
: "${ASK123_PROD_REPO:=ask123-docker-prod-local}"
: "${ASK123_DOCKER_IMAGE:=ask-123-demo}"

# ASK456 (JFrog project ask456)
: "${ASK456_VAULT_ROLE:=ask456}"
: "${ASK456_VAULT_POLICY:=ask456-pull}"
: "${ASK456_GROUP:=AZU_ARTIFACTORY_ASK456}"
: "${ASK456_PROD_REPO:=ask456-docker-prod-local}"
: "${ASK456_DOCKER_IMAGE:=ask-456-demo}"
: "${ASK456_NAMESPACE:=ask456-ns}"
: "${ASK456_WORKLOAD_SA:=workload-sa}"
: "${ASK456_K8S_AUTH_ROLE:=ask456-workload}"
: "${VAULT_K8S_AUTH_PATH:=kubernetes}"

export VAULT_ADDR VAULT_TOKEN

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd vault
require_cmd jq
require_cmd docker
require_cmd kubectl

docker_logout() {
  docker logout "${JFROG_REGISTRY}" >/dev/null 2>&1 || true
}

docker_login() {
  local username="$1"
  local token="$2"
  echo "${token}" | docker login "${JFROG_REGISTRY}" -u "${username}" --password-stdin >/dev/null
}

issue_token() {
  local role="$1"
  vault read -format=json "${PLUGIN_VAULT_PATH}/token/${role}"
}

assert_scope() {
  local resp="$1"
  local expected_group="$2"
  local scope
  scope="$(echo "${resp}" | jq -r '.data.scope')"
  [[ "${scope}" == *"${expected_group}"* ]] \
    && pass "scope includes ${expected_group} (${scope})" \
    || fail "scope missing ${expected_group}: ${scope}"
}

try_pull() {
  local image="$1"
  docker pull "${image}" >/dev/null 2>&1
}

ASK123_IMAGE="${JFROG_REGISTRY}/${ASK123_PROD_REPO}/${ASK123_DOCKER_IMAGE}:${DOCKER_TAG}"
ASK456_IMAGE="${JFROG_REGISTRY}/${ASK456_PROD_REPO}/${ASK456_DOCKER_IMAGE}:${DOCKER_TAG}"

echo "==> Issue ASK123 token (role ${ASK123_VAULT_ROLE})"
ASK123_RESP="$(issue_token "${ASK123_VAULT_ROLE}")"
ASK123_USER="$(echo "${ASK123_RESP}" | jq -r '.data.username')"
ASK123_TOKEN="$(echo "${ASK123_RESP}" | jq -r '.data.access_token')"
echo "  username: ${ASK123_USER}"
assert_scope "${ASK123_RESP}" "${ASK123_GROUP}"

echo ""
echo "==> Issue ASK456 token (role ${ASK456_VAULT_ROLE})"
ASK456_RESP="$(issue_token "${ASK456_VAULT_ROLE}")"
ASK456_USER="$(echo "${ASK456_RESP}" | jq -r '.data.username')"
ASK456_TOKEN="$(echo "${ASK456_RESP}" | jq -r '.data.access_token')"
echo "  username: ${ASK456_USER}"
assert_scope "${ASK456_RESP}" "${ASK456_GROUP}"

echo ""
echo "==> ASK123 positive: own prod repo"
docker_logout
docker_login "${ASK123_USER}" "${ASK123_TOKEN}"
try_pull "${ASK123_IMAGE}" && pass "ASK123 pulls ${ASK123_IMAGE}" || fail "ASK123 should pull own prod repo"

echo ""
echo "==> ASK123 negative: ASK456 prod repo"
docker_login "${ASK123_USER}" "${ASK123_TOKEN}"
if try_pull "${ASK456_IMAGE}"; then
  fail "ASK123 token should not pull ASK456 prod repo"
else
  pass "ASK123 denied on ASK456 prod repo"
fi

echo ""
echo "==> ASK456 positive: own prod repo"
docker_logout
docker_login "${ASK456_USER}" "${ASK456_TOKEN}"
try_pull "${ASK456_IMAGE}" && pass "ASK456 pulls ${ASK456_IMAGE}" || fail "ASK456 should pull own prod repo"

echo ""
echo "==> ASK456 negative: ASK123 prod repo"
docker_login "${ASK456_USER}" "${ASK456_TOKEN}"
if try_pull "${ASK123_IMAGE}"; then
  fail "ASK456 token should not pull ASK123 prod repo"
else
  pass "ASK456 denied on ASK123 prod repo"
fi

echo ""
echo "==> Vault policy isolation: ASK456 K8s auth cannot read ASK123 token path"
SA_JWT="$(kubectl create token "${ASK456_WORKLOAD_SA}" -n "${ASK456_NAMESPACE}" --duration=1h)"
LOGIN_RESP="$(vault write -format=json "auth/${VAULT_K8S_AUTH_PATH}/login" role="${ASK456_K8S_AUTH_ROLE}" jwt="${SA_JWT}")"
ASK456_VAULT_TOKEN="$(echo "${LOGIN_RESP}" | jq -r '.auth.client_token')"
echo "${LOGIN_RESP}" | jq -r '.auth.policies | join(",")' | grep -q "${ASK456_VAULT_POLICY}" \
  && pass "ASK456 SA login has ${ASK456_VAULT_POLICY} policy" \
  || fail "ASK456 SA missing expected policy"

if VAULT_TOKEN="${ASK456_VAULT_TOKEN}" vault read "${PLUGIN_VAULT_PATH}/token/${ASK123_VAULT_ROLE}" >/dev/null 2>&1; then
  fail "ASK456 Vault token should not read artifactory/token/${ASK123_VAULT_ROLE}"
else
  pass "ASK456 Vault token denied on artifactory/token/${ASK123_VAULT_ROLE}"
fi

if VAULT_TOKEN="${ASK456_VAULT_TOKEN}" vault read "${PLUGIN_VAULT_PATH}/token/${ASK456_VAULT_ROLE}" >/dev/null 2>&1; then
  pass "ASK456 Vault token can read artifactory/token/${ASK456_VAULT_ROLE}"
else
  fail "ASK456 Vault token should read artifactory/token/${ASK456_VAULT_ROLE}"
fi

echo ""
echo "Phase 4 multi-app isolation tests complete."
