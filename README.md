# Vault ↔ Artifactory Lab

Companion lab for the [vault-plugin-secrets-artifactory](https://github.com/jfrog/vault-plugin-secrets-artifactory) integration.

Validates the customer use-case: **Kubernetes namespace + service account → Vault Kubernetes auth → External Secrets Operator → scoped Artifactory prod image pull**.

## Quick start

1. Copy environment template and fill in sandbox values:

   ```sh
   cp .env.example .env
   # edit .env — never commit; VAULT_TOKEN=root is local dev only
   ```

2. Download the plugin and bootstrap Vault (Phase 0):

   ```sh
   cd vault-artifactory-lab
   source .env
   ./scripts/setup-vault.sh
   ```

   This downloads the pre-built binary for your OS from [GitHub releases](https://github.com/jfrog/vault-plugin-secrets-artifactory/releases) (Darwin `arm64` or `amd64`), starts a local Vault dev server if needed, and configures the `artifactory/` secrets engine.

   Re-bootstrapping after a Vault restart requires a fresh `JFROG_ACCESS_TOKEN` in `.env` — see **Note for future runs** in [docs/setup-and-validation.md](docs/setup-and-validation.md#phase-0--plugin-and-vault-bootstrap).

   To run Vault in a foreground terminal instead:

   ```sh
   ./scripts/download-plugin.sh
   ./scripts/start-vault-dev.sh          # terminal 1
   SKIP_VAULT_START=1 ./scripts/setup-vault.sh   # terminal 2
   ```

3. Follow the canonical runbook through Phases 1–3:

   **[docs/setup-and-validation.md](docs/setup-and-validation.md)**

4. Validate the automated pull path:

   ```sh
   ./scripts/demo-kubernetes-auth.sh   # Layer 2: SA → Vault
   ./scripts/demo-eso.sh               # Primary: ESO → pod pull
   ```

**Visual architecture:** [docs/visual-architecture.md](docs/visual-architecture.md)

## Lab status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Plugin + Vault bootstrap (pre-built release) | Done |
| 1 | ASK123 Artifactory RBAC + Vault role | Done |
| 2 | Vault Kubernetes auth (`ask123-workload-sa` → policy) | Done |
| 3 | External Secrets Operator (VaultDynamicSecret) | Done |
| 4 | Multi-app isolation (ASK456) | Done |

## Repository layout

| Path | Purpose |
|------|---------|
| `assets/` | Pull-verification Docker images — [inventory](assets/README.md) |
| `scripts/` | Setup and validation automation |
| `policies/` | Vault policies per CMDB app |
| `k8s/eso/` | VaultDynamicSecret + ExternalSecret manifests |
| `docs/setup-and-validation.md` | **Canonical runbook** |
| `docs/visual-architecture.md` | ERD + sequence diagrams |
| `docs/appendix/` | JFrog doc corrections, internal workflow notes |
| `internal/` | Local only — customer context (gitignored) |
| `.env.example` | Required environment variables |

## Related repos

- **Plugin releases:** [jfrog/vault-plugin-secrets-artifactory/releases](https://github.com/jfrog/vault-plugin-secrets-artifactory/releases)
- **Workspace:** `~/code/cursor-workspaces/vault-artifactory-lab.code-workspace`
