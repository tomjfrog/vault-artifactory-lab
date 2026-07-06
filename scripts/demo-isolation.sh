#!/usr/bin/env bash
# Phase 1 isolation tests for app ASK123 (positive prod pull, negative dev pull).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${DEMO_ROLE:=vaultdemo}"
: "${DOCKER_IMAGE:=lab-demo}"
: "${DOCKER_TAG:=1.0.0}"
: "${JFROG_REGISTRY:=${JFROG_URL#https://}}"

PROD_REPO="${DOCKER_PROD_REPO:-vaultdemo-docker-prod-local}"
DEV_REPO="${DOCKER_DEV_REPO:-vaultdemo-docker-local}"

export VAULT_ADDR VAULT_TOKEN

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }

docker_logout() {
  docker logout "${JFROG_REGISTRY}" >/dev/null 2>&1 || true
}

docker_login() {
  local username="$1"
  local token="$2"
  echo "${token}" | docker login "${JFROG_REGISTRY}" -u "${username}" --password-stdin >/dev/null
}

docker_rmi_if_present() {
  local image="$1"
  docker rmi -f "${image}" >/dev/null 2>&1 || true
}

echo "==> Issue token from role ${DEMO_ROLE}"
RESP="$(vault read -format=json "${PLUGIN_VAULT_PATH}/token/${DEMO_ROLE}")"
TOKEN_USERNAME="$(echo "${RESP}" | jq -r '.data.username')"
ACCESS_TOKEN="$(echo "${RESP}" | jq -r '.data.access_token')"
TOKEN_SCOPE="$(echo "${RESP}" | jq -r '.data.scope')"
echo "  username: ${TOKEN_USERNAME}"
echo "  scope:    ${TOKEN_SCOPE}"

EXPECTED_GROUP="${ARTIFACTORY_GROUP:-AZU_ARTIFACTORY_ASK123}"
if [[ "${TOKEN_SCOPE}" != *"${EXPECTED_GROUP}"* ]]; then
  fail "token scope missing ${EXPECTED_GROUP} — run ./scripts/setup-phase1-vault.sh (check .env does not override Phase 1 scope)"
fi

echo ""
echo "==> Positive test: pull prod image (authenticated, no local cache)"
PROD_IMAGE="${JFROG_REGISTRY}/${PROD_REPO}/${DOCKER_IMAGE}:${DOCKER_TAG}"
docker_logout
docker_rmi_if_present "${PROD_IMAGE}"
docker_login "${TOKEN_USERNAME}" "${ACCESS_TOKEN}"
if docker pull "${PROD_IMAGE}" >/dev/null; then
  pass "prod image pulled (${PROD_IMAGE})"
else
  fail "prod docker pull failed"
fi

echo ""
echo "==> Negative test: dev repo should be denied"
DEV_IMAGE="${JFROG_REGISTRY}/${DEV_REPO}/${DOCKER_IMAGE}:${DOCKER_TAG}"
docker_rmi_if_present "${DEV_IMAGE}"
if docker pull "${DEV_IMAGE}" >/dev/null 2>&1; then
  fail "dev image pull should have been denied (${DEV_IMAGE})"
else
  pass "dev repo pull denied (${DEV_IMAGE})"
fi

echo ""
echo "Phase 1 isolation tests complete."
