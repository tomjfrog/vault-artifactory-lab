#!/usr/bin/env bash
# Phase 0: Download pre-built plugin, start Vault dev (if needed), register, enable, admin config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${PLUGIN_NAME:=artifactory}"
: "${PLUGIN_COMMAND:=artifactory-secrets-plugin}"
: "${PLUGIN_VERSION:=v1.8.9}"
: "${PLUGIN_DIR:=${LAB_ROOT}/.vault-plugin}"
if [[ "${PLUGIN_DIR}" != /* ]]; then
  PLUGIN_DIR="${LAB_ROOT}/${PLUGIN_DIR}"
fi
export PLUGIN_DIR
: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_ACCESS_TOKEN:?Set JFROG_ACCESS_TOKEN in .env}"

VERSION_NUM="${PLUGIN_VERSION#v}"

export VAULT_ADDR VAULT_TOKEN

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd vault

echo "==> Download pre-built plugin (${PLUGIN_VERSION})"
PLUGIN_SHA="$("${SCRIPT_DIR}/download-plugin.sh")"

if ! vault status >/dev/null 2>&1; then
  if [[ "${SKIP_VAULT_START:-0}" == "1" ]]; then
    echo "ERROR: Vault not reachable at ${VAULT_ADDR}" >&2
    echo "  Start Vault in another terminal: ./scripts/start-vault-dev.sh" >&2
    exit 1
  fi
  echo "==> Vault not running — starting dev server in background"
  VAULT_DEV_BACKGROUND=1 "${SCRIPT_DIR}/start-vault-dev.sh"
fi

echo ""
echo "==> Register and enable plugin (version ${VERSION_NUM})"
if vault secrets list -format=json 2>/dev/null | jq -e --arg p "${PLUGIN_VAULT_PATH}/" '.[ $p ]' >/dev/null; then
  vault secrets disable "${PLUGIN_VAULT_PATH}" || true
fi

vault plugin register \
  -sha256="${PLUGIN_SHA}" \
  -command="${PLUGIN_COMMAND}" \
  -version="${VERSION_NUM}" \
  secret "${PLUGIN_NAME}"

vault secrets enable -path="${PLUGIN_VAULT_PATH}" -plugin-version="${VERSION_NUM}" "${PLUGIN_NAME}"

echo ""
echo "==> Write admin config and rotate bootstrap token"
vault write "${PLUGIN_VAULT_PATH}/config/admin" \
  url="${JFROG_URL}" \
  access_token="${JFROG_ACCESS_TOKEN}"
vault read "${PLUGIN_VAULT_PATH}/config/admin"
vault write -f "${PLUGIN_VAULT_PATH}/config/rotate"
vault read "${PLUGIN_VAULT_PATH}/config/admin"

echo ""
echo "Phase 0 complete."
echo "  Validate: vault secrets list | grep ${PLUGIN_VAULT_PATH}"
echo "  Next:     ./scripts/setup-phase1-artifactory.sh"
