#!/usr/bin/env bash
# Download a pre-built vault-plugin-secrets-artifactory binary from GitHub releases.
# Matches OS/arch (e.g. darwin_arm64 on Apple Silicon Mac).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${LAB_ROOT}/.env" ]] && source "${LAB_ROOT}/.env"

: "${PLUGIN_RELEASES_URL:=https://github.com/jfrog/vault-plugin-secrets-artifactory/releases}"
: "${PLUGIN_VERSION:=v1.8.9}"
: "${PLUGIN_DIR:=${LAB_ROOT}/.vault-plugin}"
if [[ "${PLUGIN_DIR}" != /* ]]; then
  PLUGIN_DIR="${LAB_ROOT}/${PLUGIN_DIR}"
fi
: "${PLUGIN_COMMAND:=artifactory-secrets-plugin}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd shasum

detect_platform() {
  local goos goarch
  case "$(uname -s)" in
    Darwin) goos=darwin ;;
    Linux) goos=linux ;;
    FreeBSD) goos=freebsd ;;
    *)
      echo "ERROR: unsupported OS: $(uname -s)" >&2
      exit 1
      ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) goarch=arm64 ;;
    x86_64|amd64) goarch=amd64 ;;
    *)
      echo "ERROR: unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
  echo "${goos}_${goarch}"
}

VERSION_TAG="${PLUGIN_VERSION}"
VERSION_NUM="${VERSION_TAG#v}"
PLATFORM="$(detect_platform)"
ASSET_NAME="${PLUGIN_COMMAND}_${VERSION_NUM}_${PLATFORM}"
DOWNLOAD_BASE="${PLUGIN_RELEASES_URL%/}/download/${VERSION_TAG}"
BINARY_PATH="${PLUGIN_DIR}/${PLUGIN_COMMAND}"
# Checksums must NOT live in PLUGIN_DIR — Vault dev mode loads every file there as a plugin.
CHECKSUMS_DIR="${LAB_ROOT}/.vault-plugin-meta"
CHECKSUMS_PATH="${CHECKSUMS_DIR}/${PLUGIN_COMMAND}_${VERSION_NUM}.checksums.txt"

mkdir -p "${PLUGIN_DIR}" "${CHECKSUMS_DIR}"

echo "==> Plugin release ${VERSION_TAG} (${PLATFORM})" >&2
echo "    Releases: ${PLUGIN_RELEASES_URL}" >&2
echo "    Asset:    ${ASSET_NAME}" >&2
echo "    Install:  ${BINARY_PATH}" >&2

if [[ -f "${BINARY_PATH}" && "${FORCE_PLUGIN_DOWNLOAD:-0}" != "1" ]]; then
  echo "  binary already present (set FORCE_PLUGIN_DOWNLOAD=1 to re-download)" >&2
else
  curl -fsSL -o "${BINARY_PATH}" "${DOWNLOAD_BASE}/${ASSET_NAME}"
  chmod +x "${BINARY_PATH}"
  echo "  downloaded ${ASSET_NAME}" >&2
fi

curl -fsSL -o "${CHECKSUMS_PATH}" "${DOWNLOAD_BASE}/${PLUGIN_COMMAND}_${VERSION_NUM}.checksums.txt"

EXPECTED_SHA="$(grep " ${ASSET_NAME}$" "${CHECKSUMS_PATH}" | awk '{print $1}')"
if [[ -z "${EXPECTED_SHA}" ]]; then
  echo "ERROR: checksum entry not found for ${ASSET_NAME} in ${CHECKSUMS_PATH}" >&2
  exit 1
fi

ACTUAL_SHA="$(shasum -a 256 "${BINARY_PATH}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]]; then
  echo "ERROR: checksum mismatch for ${BINARY_PATH}" >&2
  echo "  expected: ${EXPECTED_SHA}" >&2
  echo "  actual:   ${ACTUAL_SHA}" >&2
  exit 1
fi
echo "  checksum verified (${ACTUAL_SHA})" >&2

# stdout: SHA256 for vault plugin register (captured by setup-vault.sh)
echo "${EXPECTED_SHA}"
