#!/usr/bin/env bash
# Verify Artifactory connectivity and document group prerequisites for demo roles.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${JFROG_URL:?Set JFROG_URL in .env}"
: "${JFROG_ACCESS_TOKEN:?Set JFROG_ACCESS_TOKEN in .env}"

echo "==> Ping Artifactory..."
curl -sf "${JFROG_URL}/artifactory/api/system/ping"
echo " OK"

echo "==> Verify admin token..."
curl -sf -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/access/api/v1/tokens/me" | jq .

echo ""
echo "==> Demo groups to create in Artifactory UI (if not present):"
echo "  - automation   (CI/CD demo role)"
echo "  - demo-readers (read-only scoped token demo)"
echo "  - test-group   (scope override demo)"
echo ""
echo "Administration → Access Management → Groups"
echo ""
echo "The 'readers' group usually exists by default and can be used for basic demos."
