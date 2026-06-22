#!/usr/bin/env bash
# Run progressive demo scenarios for the Vault ↔ Artifactory integration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${PLUGIN_VAULT_PATH:=artifactory}"
: "${ARTIFACTORY_SCOPE:=applied-permissions/groups:readers}"

export VAULT_ADDR VAULT_TOKEN

section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

section "Scenario 1 — CI role and token"
vault write "${PLUGIN_VAULT_PATH}/roles/jenkins" \
  scope="${ARTIFACTORY_SCOPE}" \
  default_ttl=1h max_ttl=3h

vault read "${PLUGIN_VAULT_PATH}/roles/jenkins"
vault read "${PLUGIN_VAULT_PATH}/token/jenkins"

section "Scenario 2 — List roles"
vault list "${PLUGIN_VAULT_PATH}/roles"

section "Scenario 3 — Read admin config (version detection)"
vault read "${PLUGIN_VAULT_PATH}/config/admin"

echo ""
echo "Demo complete. For scope-override and user-token scenarios, see docs/architecture.md"
