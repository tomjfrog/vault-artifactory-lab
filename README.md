# Vault ↔ Artifactory Lab

Companion lab for the [vault-plugin-secrets-artifactory](https://github.com/jfrog/vault-plugin-secrets-artifactory) integration.

This repository holds **lab setup, demo scripts, and customer-facing runbooks**. The plugin source lives in a separate repo (`vault-plugin-secrets-artifactory`).

## Prerequisites

- JFrog Cloud sandbox or Artifactory 7.42.1+ (7.50.3+ for expiring tokens)
- [HashiCorp Vault CLI](https://developer.hashicorp.com/vault/docs/install)
- Go 1.25+, GoReleaser (to build the plugin from source)
- `curl`, `jq`

## Quick start

1. Copy the environment template and fill in your sandbox values:

   ```sh
   cp .env.example .env
   # edit .env — never commit this file
   ```

2. Build the plugin (in the sibling `vault-plugin-secrets-artifactory` repo):

   ```sh
   cd ../vault-plugin-secrets-artifactory
   make build
   ```

3. Start Vault and configure the plugin:

   ```sh
   source .env
   ./scripts/setup-vault.sh
   ```

4. Prepare Artifactory groups and verify connectivity:

   ```sh
   ./scripts/setup-artifactory.sh
   ```

5. Run the demo scenarios:

   ```sh
   ./scripts/demo.sh
   ```

## Repository layout

| Path | Purpose |
|------|---------|
| `scripts/` | Setup and demo automation |
| `policies/` | Vault policies for lab roles |
| `docs/` | Architecture notes and customer-facing deep dives |
| `internal/` | **Local only** — specs, discovery notes, customer context (gitignored) |
| `.env.example` | Required environment variables (no secrets) |

## Related repos

- **Plugin source:** [jfrog/vault-plugin-secrets-artifactory](https://github.com/jfrog/vault-plugin-secrets-artifactory)
- **Workspace:** open `~/code/cursor-workspaces/vault-artifactory-lab.code-workspace` in Cursor to work across both repos

## Lab status

See [docs/lab-log.md](docs/lab-log.md) for executed steps, decisions, and version history.
