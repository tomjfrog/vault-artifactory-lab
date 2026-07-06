#!/usr/bin/env bash
# Phase 1b: Vault role + policy for CMDB app ASK123 (JFrog project ask123).
# Prerequisites: ./scripts/setup-phase1-artifactory.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${ASK123_ID:=ASK123}"
: "${ASK123_GROUP:=AZU_ARTIFACTORY_${ASK123_ID}}"
: "${ASK123_VAULT_ROLE:=ask123}"
: "${ASK123_VAULT_POLICY:=ask123-pull}"
PHASE1_SCOPE="applied-permissions/groups:${ASK123_GROUP}"

export VAULT_ADDR VAULT_TOKEN

echo "==> Writing Vault policy ${ASK123_VAULT_POLICY}"
vault policy write "${ASK123_VAULT_POLICY}" "${LAB_ROOT}/policies/${ASK123_VAULT_POLICY}.hcl"

echo "==> Writing plugin role ${ASK123_VAULT_ROLE} (scope: ${PHASE1_SCOPE})"
vault write "${PLUGIN_VAULT_PATH}/roles/${ASK123_VAULT_ROLE}" \
  scope="${PHASE1_SCOPE}" \
  default_ttl=1h max_ttl=3h

echo "==> Verifying role"
vault read "${PLUGIN_VAULT_PATH}/roles/${ASK123_VAULT_ROLE}"

echo ""
echo "Issue a token: vault read ${PLUGIN_VAULT_PATH}/token/${ASK123_VAULT_ROLE}"
echo "Then run: ./scripts/demo-isolation.sh"
