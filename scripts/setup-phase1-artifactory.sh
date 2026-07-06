#!/usr/bin/env bash
# Phase 1a: Artifactory RBAC for CMDB app ASK123 (JFrog project ask123).
# Creates project, group, dev+prod Docker repos, permission target, and publishes ask-123-demo image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID in .env}"
: "${ASK123_ID:=ASK123}"
: "${ASK123_PROJECT:=ask123}"
: "${ASK123_GROUP:=AZU_ARTIFACTORY_${ASK123_ID}}"
: "${ASK123_DEV_REPO:=ask123-docker-dev-local}"
: "${ASK123_PROD_REPO:=ask123-docker-prod-local}"
: "${ASK123_PERMISSION:=ask123-docker-prod-pull}"
: "${ASK123_DOCKER_IMAGE:=ask-123-demo}"
: "${DOCKER_TAG:=1.0.0}"
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
  jf api "/access/api/v2/groups/${ASK123_GROUP}" --server-id "${JFROG_SERVER_ID}" 2>&1 \
    | grep -q "Http Status: 200"
}

permission_exists() {
  jf api "/access/api/v2/permissions/${ASK123_PERMISSION}" --server-id "${JFROG_SERVER_ID}" 2>&1 \
    | grep -q "Http Status: 200"
}

project_exists() {
  jf api "/access/api/v1/projects/${ASK123_PROJECT}" --server-id "${JFROG_SERVER_ID}" 2>&1 \
    | grep -q "Http Status: 200"
}

repo_exists() {
  local repo_key="$1"
  local code
  code="$(jf rt curl -s -o /dev/null -w "%{http_code}" -XGET "/api/repositories/${repo_key}" --server-id "${JFROG_SERVER_ID}" || true)"
  [[ "${code}" == "200" ]]
}

create_docker_repo() {
  local repo_key="$1"
  local env_label="$2"
  local description="$3"

  if repo_exists "${repo_key}"; then
    echo "  repository ${repo_key} already exists"
    return
  fi

  jf rt curl -XPUT "/api/repositories/${repo_key}" --server-id "${JFROG_SERVER_ID}" \
    -H "Content-Type: application/json" \
    -d "{
      \"key\": \"${repo_key}\",
      \"rclass\": \"local\",
      \"packageType\": \"docker\",
      \"description\": \"${description}\",
      \"projectKey\": \"${ASK123_PROJECT}\",
      \"environments\": [\"${env_label}\"],
      \"dockerApiVersion\": \"V2\",
      \"enableDockerSupport\": true
    }"
  echo "  created repository ${repo_key} (${env_label})"
}

publish_image() {
  local repo_key="$1"
  local image="${JFROG_REGISTRY}/${repo_key}/${ASK123_DOCKER_IMAGE}:${DOCKER_TAG}"
  docker build -t "${image}" -f "${LAB_ROOT}/assets/Dockerfile.ask123" "${LAB_ROOT}/assets"
  jf docker push "${image}" --server-id "${JFROG_SERVER_ID}" || {
    echo "Note: verify push with: docker pull ${image}"
  }
  echo "  published ${image}"
}

echo "==> Create JFrog project ${ASK123_PROJECT} (${ASK123_ID})"
if project_exists; then
  echo "  project ${ASK123_PROJECT} already exists"
else
  jf api /access/api/v1/projects --server-id "${JFROG_SERVER_ID}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"project_key\": \"${ASK123_PROJECT}\",
      \"display_name\": \"${ASK123_ID}\",
      \"description\": \"CMDB app ${ASK123_ID} — Vault lab\"
    }"
  echo "  created project ${ASK123_PROJECT}"
fi

echo ""
echo "==> Create group ${ASK123_GROUP}"
if group_exists; then
  echo "  group ${ASK123_GROUP} already exists"
else
  jf api /access/api/v2/groups --server-id "${JFROG_SERVER_ID}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${ASK123_GROUP}\",
      \"description\": \"CMDB app ${ASK123_ID} — Vault lab prod pull\",
      \"auto_join\": false,
      \"admin_privileges\": false
    }"
  echo "  created group ${ASK123_GROUP}"
fi

echo ""
echo "==> Create Docker repositories (dev + prod)"
create_docker_repo "${ASK123_DEV_REPO}" "DEV" "Dev Docker/OCI images for ${ASK123_ID}"
create_docker_repo "${ASK123_PROD_REPO}" "PROD" "Prod Docker/OCI images for ${ASK123_ID}"

echo ""
echo "==> Create permission target ${ASK123_PERMISSION} (READ on prod repo only)"
if permission_exists; then
  echo "  permission ${ASK123_PERMISSION} already exists"
else
  jf api /access/api/v2/permissions --server-id "${JFROG_SERVER_ID}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${ASK123_PERMISSION}\",
      \"resources\": {
        \"artifact\": {
          \"actions\": {
            \"users\": {},
            \"groups\": {
              \"${ASK123_GROUP}\": [\"READ\"]
            }
          },
          \"targets\": {
            \"${ASK123_PROD_REPO}\": {
              \"include_patterns\": [\"**\"],
              \"exclude_patterns\": []
            }
          }
        }
      }
    }"
  echo "  created permission ${ASK123_PERMISSION}"
fi

echo ""
echo "==> Build and publish ${ASK123_DOCKER_IMAGE}:${DOCKER_TAG}"
publish_image "${ASK123_DEV_REPO}"
publish_image "${ASK123_PROD_REPO}"

echo ""
echo "Phase 1 Artifactory provisioning complete (project ${ASK123_PROJECT})."
echo "  Verify prod: docker pull ${JFROG_REGISTRY}/${ASK123_PROD_REPO}/${ASK123_DOCKER_IMAGE}:${DOCKER_TAG}"
echo "  Next: ./scripts/setup-phase1-vault.sh"
