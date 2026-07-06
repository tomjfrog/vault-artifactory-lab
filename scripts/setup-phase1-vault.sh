#!/usr/bin/env bash
# Phase 1 Vault configuration for app ASK123 / project vaultdemo.
# Prerequisites: Artifactory group AZU_ARTIFACTORY_ASK123 and permission target exist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${DEMO_ROLE:=vaultdemo}"
: "${ASK_ID:=ASK123}"
: "${ARTIFACTORY_GROUP:=AZU_ARTIFACTORY_${ASK_ID}}"
# Always derive Phase 1 scope from ASK group — do not reuse unrelated .env overrides.
PHASE1_SCOPE="applied-permissions/groups:${ARTIFACTORY_GROUP}"

export VAULT_ADDR VAULT_TOKEN

echo "==> Writing Vault policy vaultdemo-ask123-pull"
vault policy write vaultdemo-ask123-pull "${LAB_ROOT}/policies/vaultdemo-ask123-pull.hcl"

echo "==> Writing plugin role ${DEMO_ROLE} (scope: ${PHASE1_SCOPE})"
vault write "${PLUGIN_VAULT_PATH}/roles/${DEMO_ROLE}" \
  scope="${PHASE1_SCOPE}" \
  default_ttl=1h max_ttl=3h

echo "==> Verifying role"
vault read "${PLUGIN_VAULT_PATH}/roles/${DEMO_ROLE}"

echo ""
echo "Issue a token: vault read ${PLUGIN_VAULT_PATH}/token/${DEMO_ROLE}"
echo "Then run: ./scripts/demo-isolation.sh"
