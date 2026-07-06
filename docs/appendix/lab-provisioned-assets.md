# Lab-provisioned JFrog and Vault assets

Extended inventory with verify commands. **Canonical runbook:** [../setup-and-validation.md](../setup-and-validation.md).

**Entity relationships:** [../visual-architecture.md](../visual-architecture.md)

## Project

| Field | Value |
|-------|-------|
| Display name | Vault Demo |
| Project key | `vaultdemo` |
| Description | JFrog Project for the Vault ↔ Artifactory secrets plugin lab demo |
| Created | MCP `jfrog_create_project` (2026-06-22) |

## Access control (ASK123)

| Field | Value |
|-------|-------|
| CMDB application ID | `ASK123` |
| Artifactory group | `AZU_ARTIFACTORY_ASK123` |
| Permission target | `vaultdemo-ask123-prod-pull` |
| Group permissions | **READ** on `vaultdemo-docker-prod-local/**` only |
| Created | Group via `POST /access/api/v2/groups`; permission target via MCP (2026-06-22) |

Verify:

```bash
jf api /access/api/v2/groups/AZU_ARTIFACTORY_ASK123 --server-id "${JFROG_SERVER_ID}"
jf api /access/api/v2/permissions/vaultdemo-ask123-prod-pull --server-id "${JFROG_SERVER_ID}"
```

## Docker repositories

### Development (`vaultdemo-docker-local`)

| Field | Value |
|-------|-------|
| Repository key | `vaultdemo-docker-local` |
| Type | Local |
| Package type | Docker |
| Project | `vaultdemo` |
| Environment | DEV |
| Registry URL | `YOUR-TENANT.jfrog.io/vaultdemo-docker-local/` |
| ASK123 access | **Not granted** — used for negative isolation tests |

### Production (`vaultdemo-docker-prod-local`)

| Field | Value |
|-------|-------|
| Repository key | `vaultdemo-docker-prod-local` |
| Type | Local |
| Package type | Docker |
| Project | `vaultdemo` |
| Environment | PROD |
| Registry URL | `YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/` |
| ASK123 access | **READ** via group `AZU_ARTIFACTORY_ASK123` |
| Created | MCP `jfrog_create_local_repository` (2026-06-22) |

## Demo Docker image

| Field | Value |
|-------|-------|
| Source | `assets/Dockerfile.ask123` (Alpine 3.21) |
| Image name | `lab-demo` |
| Tag | `1.0.0` |
| Dev reference | `YOUR-TENANT.jfrog.io/vaultdemo-docker-local/lab-demo:1.0.0` |
| Prod reference | `YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/lab-demo:1.0.0` |
| Purpose | Prints `Successful Image Pull from Artifactory` when run |

Build and publish: [assets/README.md](../assets/README.md) (ASK123-only asset inventory).

Publish to dev:

```bash
./assets/publish.sh
```

Publish to prod (direct):

```bash
DOCKER_REPO=vaultdemo-docker-prod-local ./assets/publish.sh
```

Promote dev → prod (CI-style alternative):

```bash
jf rt docker-promote lab-demo vaultdemo-docker-local vaultdemo-docker-prod-local \
  --source-tag=1.0.0 --copy=true --server-id "${JFROG_SERVER_ID}"
```

## Access control (ASK456 — Phase 4)

| Field | Value |
|-------|-------|
| CMDB application ID | `ASK456` |
| Artifactory group | `AZU_ARTIFACTORY_ASK456` |
| Permission target | `vaultdemo-ask456-prod-pull` |
| Group permissions | **READ** on `vaultdemo-docker-ask456-prod-local/**` only |
| Created | `setup-phase4-artifactory.sh` (2026-06-22) |

Verify:

```bash
jf api /access/api/v2/groups/AZU_ARTIFACTORY_ASK456 --server-id "${JFROG_SERVER_ID}"
jf api /access/api/v2/permissions/vaultdemo-ask456-prod-pull --server-id "${JFROG_SERVER_ID}"
```

### Production (`vaultdemo-docker-ask456-prod-local`)

| Field | Value |
|-------|-------|
| Repository key | `vaultdemo-docker-ask456-prod-local` |
| Type | Local Docker |
| Project | `vaultdemo` |
| Environment | PROD |
| Registry URL | `YOUR-TENANT.jfrog.io/vaultdemo-docker-ask456-prod-local/` |
| ASK456 access | **READ** via group `AZU_ARTIFACTORY_ASK456` |
| Image | `lab-demo-ask456:1.0.0` (`assets/Dockerfile.ask456`) |

## Vault resources (local dev server)

| Resource | Path / name | Purpose |
|----------|-------------|---------|
| Secrets engine | `artifactory/` | **Plugin** mount (dynamic tokens — not KV). ESO: [eso-vault-dynamic-secret.md](eso-vault-dynamic-secret.md) |
| Admin config | `artifactory/config/admin` | Artifactory URL + bootstrap token |
| Role (Phase 1) | `artifactory/roles/vaultdemo` | Scope `applied-permissions/groups:AZU_ARTIFACTORY_ASK123` |
| Token path | `artifactory/token/vaultdemo` | Issue scoped pull credentials |
| Policy | `vaultdemo-ask123-pull` | Allows read of `artifactory/token/vaultdemo` |
| K8s auth role | `auth/kubernetes/role/vaultdemo-workload` | Binds `workload-sa` in `vaultdemo-ns` to policy |
| Role (Phase 4) | `artifactory/roles/vaultdemo-ask456` | Scope `applied-permissions/groups:AZU_ARTIFACTORY_ASK456` |
| Token path (Phase 4) | `artifactory/token/vaultdemo-ask456` | Issue ASK456 scoped pull credentials |
| Policy (Phase 4) | `vaultdemo-ask456-pull` | Allows read of `artifactory/token/vaultdemo-ask456` |
| K8s auth role (Phase 4) | `auth/kubernetes/role/vaultdemo-ask456-workload` | Binds `workload-sa` in `vaultdemo-ask456-ns` |

Apply Phase 1 Vault config:

```bash
./scripts/setup-phase1-vault.sh
```

Apply Phase 2 Kubernetes auth:

```bash
./scripts/setup-kubernetes-auth.sh
./scripts/demo-kubernetes-auth.sh
```

Apply Phase 4 multi-app:

```bash
./scripts/setup-phase4-artifactory.sh
./scripts/setup-phase4-vault.sh
./scripts/demo-isolation-multi-app.sh
```

## Kubernetes resources (local Rancher Desktop k3s)

| Resource | Namespace | Notes |
|----------|-----------|-------|
| Namespace | `vaultdemo-ns` | Lab workloads |
| Service account | `workload-sa` | Vault Kubernetes auth workload identity (Phase 2) |
| Service account | `kube-system/vault-auth` | Vault token reviewer for `auth/kubernetes` |
| Secret | `artifactory-pull` | `kubernetes.io/dockerconfigjson` (Phase 3 ESO) |
| Pod | `lab-demo-eso` | Pulls prod image via ESO-synced secret (primary validation) |

### ESO (Phase 3 — ASK123 namespace)

| Resource | Namespace | Notes |
|----------|-----------|-------|
| VaultDynamicSecret | `vaultdemo-ns` | Generator: GET `artifactory/token/vaultdemo` via K8s auth |
| ExternalSecret | `vaultdemo-ns` | Syncs to `artifactory-pull`; `refreshInterval: 1h` |
| Operator | `external-secrets` | Helm-installed External Secrets Operator |

### ASK456 namespace (Phase 4)

| Resource | Namespace | Notes |
|----------|-----------|-------|
| Namespace | `vaultdemo-ask456-ns` | ASK456 workloads |
| Service account | `workload-sa` | Vault K8s auth for ASK456 policy |

Runbook: [../setup-and-validation.md](../setup-and-validation.md). Break-glass manual pull: [break-glass-manual-pull.md](break-glass-manual-pull.md).

## Provisioning methods

| Method | Used for |
|--------|----------|
| JFrog Experimental MCP | Project, Docker repos, permission target |
| `jf api` (Access API) | Group `AZU_ARTIFACTORY_ASK123` |
| JFrog CLI | Image push, promote, verification |
| Lab scripts | Vault config, isolation tests, demos |
| `docker build` / `jf docker push` | Lab image |

## Demo usage (Phase 1 — ASK123)

Issue token (single read — username and token must come from the same response):

```bash
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root

RESP=$(vault read -format=json artifactory/token/vaultdemo)
USERNAME=$(echo "$RESP" | jq -r '.data.username')
TOKEN=$(echo "$RESP" | jq -r '.data.access_token')

echo "$TOKEN" | docker login YOUR-TENANT.jfrog.io -u "$USERNAME" --password-stdin
docker pull YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/lab-demo:1.0.0
docker run --rm YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/lab-demo:1.0.0
```

Automated validation:

```bash
./scripts/demo-eso.sh              # primary end-to-end
./scripts/demo-isolation.sh        # optional Layer 1 RBAC
```
