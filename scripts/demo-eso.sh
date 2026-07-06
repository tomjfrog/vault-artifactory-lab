#!/usr/bin/env bash
# Phase 3 validation: ESO-synced docker pull secret → prod image pod.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${K8S_NAMESPACE:=vaultdemo-ns}"
: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_REGISTRY:=${JFROG_URL#https://}}"
: "${DOCKER_PROD_REPO:=vaultdemo-docker-prod-local}"
: "${DOCKER_IMAGE:=lab-demo}"
: "${DOCKER_TAG:=1.0.0}"
: "${ESO_WAIT_TIMEOUT:=180}"

PROD_IMAGE="${JFROG_REGISTRY}/${DOCKER_PROD_REPO}/${DOCKER_IMAGE}:${DOCKER_TAG}"
POD_NAME="lab-demo-eso"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd jq

echo "==> ExternalSecret status"
if ! kubectl wait --for=condition=Ready externalsecret/artifactory-pull -n "${K8S_NAMESPACE}" --timeout="${ESO_WAIT_TIMEOUT}s"; then
  echo "--- ExternalSecret describe ---"
  kubectl describe externalsecret artifactory-pull -n "${K8S_NAMESPACE}" | tail -30
  echo "--- VaultDynamicSecret describe ---"
  kubectl describe vaultdynamicsecret artifactory-vaultdemo-token -n "${K8S_NAMESPACE}" | tail -30 2>/dev/null || true
  fail "ExternalSecret not Ready within ${ESO_WAIT_TIMEOUT}s"
fi
pass "ExternalSecret artifactory-pull is Ready"

echo ""
echo "==> Synced secret artifactory-pull"
SECRET_TYPE="$(kubectl get secret artifactory-pull -n "${K8S_NAMESPACE}" -o jsonpath='{.type}')"
[[ "${SECRET_TYPE}" == "kubernetes.io/dockerconfigjson" ]] \
  && pass "secret type is kubernetes.io/dockerconfigjson" \
  || fail "unexpected secret type: ${SECRET_TYPE}"

DOCKER_CFG="$(kubectl get secret artifactory-pull -n "${K8S_NAMESPACE}" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d)"
echo "${DOCKER_CFG}" | jq -e --arg reg "${JFROG_REGISTRY}" '.auths[$reg].username' >/dev/null \
  && pass "dockerconfigjson contains registry ${JFROG_REGISTRY} username" \
  || fail "dockerconfigjson missing expected registry entry"

echo ""
echo "==> Run test pod (imagePullSecrets only — no manual vault read)"
kubectl delete pod "${POD_NAME}" -n "${K8S_NAMESPACE}" --ignore-not-found --wait=true 2>/dev/null || true

kubectl run "${POD_NAME}" \
  --namespace "${K8S_NAMESPACE}" \
  --image="${PROD_IMAGE}" \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"artifactory-pull"}]}}' \
  --restart=Never \
  --command -- sh -c 'echo Successful Image Pull from Artifactory; sleep 3600'

kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n "${K8S_NAMESPACE}" --timeout=120s
LOGS="$(kubectl logs "${POD_NAME}" -n "${K8S_NAMESPACE}")"
echo "${LOGS}"
echo "${LOGS}" | grep -q "Successful Image Pull from Artifactory" \
  && pass "pod pulled and ran prod image (${PROD_IMAGE})" \
  || fail "pod did not log expected success message"

echo ""
echo "Phase 3 ESO validation complete."
