#!/usr/bin/env bash
# Phase 1 isolation tests for CMDB app ASK123 (JFrog project ask123).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${ASK123_VAULT_ROLE:=ask123}"
: "${ASK123_DOCKER_IMAGE:=ask-123-demo}"
: "${ASK123_PROD_REPO:=ask123-docker-prod-local}"
: "${ASK123_DEV_REPO:=ask123-docker-dev-local}"
: "${ASK123_GROUP:=AZU_ARTIFACTORY_ASK123}"
: "${DOCKER_TAG:=1.0.0}"
: "${JFROG_REGISTRY:=${JFROG_URL#https://}}"

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

echo "==> Issue token from role ${ASK123_VAULT_ROLE}"
RESP="$(vault read -format=json "${PLUGIN_VAULT_PATH}/token/${ASK123_VAULT_ROLE}")"
TOKEN_USERNAME="$(echo "${RESP}" | jq -r '.data.username')"
ACCESS_TOKEN="$(echo "${RESP}" | jq -r '.data.access_token')"
TOKEN_SCOPE="$(echo "${RESP}" | jq -r '.data.scope')"
echo "  username: ${TOKEN_USERNAME}"
echo "  scope:    ${TOKEN_SCOPE}"

if [[ "${TOKEN_SCOPE}" != *"${ASK123_GROUP}"* ]]; then
  fail "token scope missing ${ASK123_GROUP} — run ./scripts/setup-phase1-vault.sh"
fi

echo ""
echo "==> Positive test: pull prod image (authenticated, no local cache)"
PROD_IMAGE="${JFROG_REGISTRY}/${ASK123_PROD_REPO}/${ASK123_DOCKER_IMAGE}:${DOCKER_TAG}"
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
DEV_IMAGE="${JFROG_REGISTRY}/${ASK123_DEV_REPO}/${ASK123_DOCKER_IMAGE}:${DOCKER_TAG}"
docker_rmi_if_present "${DEV_IMAGE}"
if docker pull "${DEV_IMAGE}" >/dev/null 2>&1; then
  fail "dev image pull should have been denied (${DEV_IMAGE})"
else
  pass "dev repo pull denied (${DEV_IMAGE})"
fi

echo ""
echo "Phase 1 isolation tests complete."
