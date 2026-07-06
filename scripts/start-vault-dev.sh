#!/usr/bin/env bash
# Start Vault dev server with the downloaded plugin binary in -dev-plugin-dir.
# Run in a dedicated terminal, or let setup-vault.sh start it in the background.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_DIR:=${LAB_ROOT}/.vault-plugin}"
if [[ "${PLUGIN_DIR}" != /* ]]; then
  PLUGIN_DIR="${LAB_ROOT}/${PLUGIN_DIR}"
fi
export PLUGIN_DIR
: "${PLUGIN_COMMAND:=artifactory-secrets-plugin}"
: "${VAULT_DEV_LOG:=${LAB_ROOT}/.vault-dev.log}"
: "${VAULT_DEV_PID_FILE:=${LAB_ROOT}/.vault-dev.pid}"

BINARY_PATH="${PLUGIN_DIR}/${PLUGIN_COMMAND}"

if [[ ! -x "${BINARY_PATH}" ]]; then
  echo "ERROR: plugin binary not found at ${BINARY_PATH}" >&2
  echo "  Run: ./scripts/download-plugin.sh" >&2
  exit 1
fi

export VAULT_ADDR VAULT_TOKEN

if vault status >/dev/null 2>&1; then
  echo "Vault already running at ${VAULT_ADDR}"
  vault status
  exit 0
fi

if [[ "${VAULT_DEV_BACKGROUND:-0}" == "1" ]]; then
  echo "==> Starting Vault dev server in background (plugin dir: ${PLUGIN_DIR})"
  nohup vault server -dev \
    -dev-root-token-id="${VAULT_TOKEN}" \
    -dev-plugin-dir="${PLUGIN_DIR}" \
    -log-level=DEBUG \
    > "${VAULT_DEV_LOG}" 2>&1 &
  echo $! > "${VAULT_DEV_PID_FILE}"
  for _ in $(seq 1 30); do
    if vault status >/dev/null 2>&1; then
      echo "  Vault ready at ${VAULT_ADDR} (pid $(cat "${VAULT_DEV_PID_FILE}"), log ${VAULT_DEV_LOG})"
      exit 0
    fi
    sleep 1
  done
  echo "ERROR: Vault did not become ready within 30s — see ${VAULT_DEV_LOG}" >&2
  exit 1
fi

echo "==> Starting Vault dev server (foreground)"
echo "    Plugin dir: ${PLUGIN_DIR}"
echo "    API:        ${VAULT_ADDR}"
echo ""
exec vault server -dev \
  -dev-root-token-id="${VAULT_TOKEN}" \
  -dev-plugin-dir="${PLUGIN_DIR}" \
  -log-level=DEBUG
