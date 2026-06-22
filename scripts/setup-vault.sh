#!/usr/bin/env bash
# Bootstrap Vault dev server plugin registration and Artifactory config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_REPO:=../vault-plugin-secrets-artifactory}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_ACCESS_TOKEN:?Set JFROG_ACCESS_TOKEN in .env}"

PLUGIN_REPO="$(cd "${LAB_ROOT}/${PLUGIN_REPO}" 2>/dev/null && pwd || cd "${PLUGIN_REPO}" && pwd)"

echo "==> Plugin repo: ${PLUGIN_REPO}"
echo "==> Vault:       ${VAULT_ADDR}"
echo "==> Artifactory: ${JFROG_URL}"
echo ""
echo "Prerequisite: Vault dev server must be running in another terminal:"
echo "  cd ${PLUGIN_REPO} && make start"
echo ""
read -r -p "Press Enter when Vault is running, or Ctrl-C to abort..."

export VAULT_ADDR VAULT_TOKEN

echo "==> Registering and enabling plugin..."
make -C "${PLUGIN_REPO}" setup

echo "==> Writing admin config and rotating token..."
make -C "${PLUGIN_REPO}" admin \
  JFROG_URL="${JFROG_URL}" \
  JFROG_ACCESS_TOKEN="${JFROG_ACCESS_TOKEN}"

echo "==> Verifying config..."
vault read "${PLUGIN_VAULT_PATH}/config/admin"

echo ""
echo "Done. Next: ./scripts/setup-artifactory.sh (optional) then ./scripts/demo.sh"
