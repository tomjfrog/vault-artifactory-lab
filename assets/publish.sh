#!/usr/bin/env bash
# Build and publish the ASK123 lab demo Docker image (lab-demo) to Artifactory.
# ASK456 uses setup-phase4-artifactory.sh with Dockerfile.ask456.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID in .env}"
: "${DOCKER_REPO:=vaultdemo-docker-local}"
: "${DOCKER_IMAGE:=lab-demo}"
: "${DOCKER_TAG:=1.0.0}"

REGISTRY="${JFROG_URL#https://}"
IMAGE="${REGISTRY}/${DOCKER_REPO}/${DOCKER_IMAGE}:${DOCKER_TAG}"

DOCKERFILE="${DOCKERFILE:-Dockerfile.ask123}"

echo "==> Building ${IMAGE} (from ${DOCKERFILE})"
docker build -t "${IMAGE}" -f "${SCRIPT_DIR}/${DOCKERFILE}" "${SCRIPT_DIR}"

echo "==> Pushing ${IMAGE}"
jf docker push "${IMAGE}" --server-id "${JFROG_SERVER_ID}" || {
  echo "Note: jf docker push may warn about docker.sock after layers are uploaded."
  echo "Verify with: docker pull ${IMAGE}"
}

echo "==> Smoke test"
docker run --rm "${IMAGE}"
