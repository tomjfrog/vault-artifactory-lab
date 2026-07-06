#!/usr/bin/env bash
# Phase 4: Artifactory RBAC for second CMDB app ASK456 (group, prod repo, permission, image).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID in .env}"
: "${ASK456_ID:=ASK456}"
: "${ASK456_GROUP:=AZU_ARTIFACTORY_${ASK456_ID}}"
: "${ASK456_PROD_REPO:=vaultdemo-docker-ask456-prod-local}"
: "${ASK456_PERMISSION:=vaultdemo-ask456-prod-pull}"
: "${ASK456_DOCKER_IMAGE:=lab-demo-ask456}"
: "${DOCKER_TAG:=1.0.0}"
: "${JFROG_PROJECT:=vaultdemo}"
: "${JFROG_REGISTRY:=${JFROG_URL#https://}}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd jf
require_cmd docker

group_exists() {
  jf api "/access/api/v2/groups/${ASK456_GROUP}" --server-id "${JFROG_SERVER_ID}" 2>&1 \
    | grep -q "Http Status: 200"
}

permission_exists() {
  jf api "/access/api/v2/permissions/${ASK456_PERMISSION}" --server-id "${JFROG_SERVER_ID}" 2>&1 \
    | grep -q "Http Status: 200"
}

echo "==> Create group ${ASK456_GROUP}"
if group_exists; then
  echo "  group ${ASK456_GROUP} already exists"
else
  jf api /access/api/v2/groups --server-id "${JFROG_SERVER_ID}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${ASK456_GROUP}\",
      \"description\": \"CMDB app ${ASK456_ID} — Vault lab prod pull (Phase 4)\",
      \"auto_join\": false,
      \"admin_privileges\": false
    }"
  echo "  created group ${ASK456_GROUP}"
fi

echo ""
echo "==> Create prod Docker repository ${ASK456_PROD_REPO}"
REPO_CODE="$(jf rt curl -s -o /dev/null -w "%{http_code}" -XGET "/api/repositories/${ASK456_PROD_REPO}" --server-id "${JFROG_SERVER_ID}" || true)"
if [[ "${REPO_CODE}" == "200" ]]; then
  echo "  repository ${ASK456_PROD_REPO} already exists"
else
  jf rt curl -XPUT "/api/repositories/${ASK456_PROD_REPO}" --server-id "${JFROG_SERVER_ID}" \
    -H "Content-Type: application/json" \
    -d "{
      \"key\": \"${ASK456_PROD_REPO}\",
      \"rclass\": \"local\",
      \"packageType\": \"docker\",
      \"description\": \"Production Docker/OCI images for app ${ASK456_ID} (project ${JFROG_PROJECT})\",
      \"projectKey\": \"${JFROG_PROJECT}\",
      \"environments\": [\"PROD\"],
      \"dockerApiVersion\": \"V2\",
      \"enableDockerSupport\": true
    }"
  echo "  created repository ${ASK456_PROD_REPO}"
fi

echo ""
echo "==> Create permission target ${ASK456_PERMISSION}"
if permission_exists; then
  echo "  permission ${ASK456_PERMISSION} already exists"
else
  jf api /access/api/v2/permissions --server-id "${JFROG_SERVER_ID}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${ASK456_PERMISSION}\",
      \"resources\": {
        \"artifact\": {
          \"actions\": {
            \"users\": {},
            \"groups\": {
              \"${ASK456_GROUP}\": [\"READ\"]
            }
          },
          \"targets\": {
            \"${ASK456_PROD_REPO}\": {
              \"include_patterns\": [\"**\"],
              \"exclude_patterns\": []
            }
          }
        }
      }
    }"
  echo "  created permission ${ASK456_PERMISSION}"
fi

echo ""
echo "==> Build and publish ${ASK456_DOCKER_IMAGE}:${DOCKER_TAG}"
IMAGE="${JFROG_REGISTRY}/${ASK456_PROD_REPO}/${ASK456_DOCKER_IMAGE}:${DOCKER_TAG}"
docker build -t "${IMAGE}" -f "${LAB_ROOT}/assets/Dockerfile.ask456" "${LAB_ROOT}/assets"
jf docker push "${IMAGE}" --server-id "${JFROG_SERVER_ID}" || {
  echo "Note: verify push with: docker pull ${IMAGE}"
}

echo ""
echo "Phase 4 Artifactory provisioning complete."
echo "  Verify: docker pull ${IMAGE}"
echo "  Next: ./scripts/setup-phase4-vault.sh"
