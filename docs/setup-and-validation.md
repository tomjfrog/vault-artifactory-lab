# Lab setup and validation

Canonical runbook for the Vault ↔ Artifactory lab: **namespace + service account → Vault Kubernetes auth → ESO → scoped Artifactory prod pull**.

**Visual architecture (ERD + sequence diagrams):** [visual-architecture.md](visual-architecture.md)

---

## Customer use-case

Map each **Kubernetes namespace + workload service account** to a **CMDB application (ASK ID)** so workloads pull **production Docker images only** from Artifactory — without operator-held Vault root tokens.

| Layer | Binds | Lab example (ASK123) |
|-------|-------|----------------------|
| 1 — Artifactory RBAC | CMDB → group → permission → prod repo | `ASK123` → `AZU_ARTIFACTORY_ASK123` → READ on `ask123-docker-prod-local` |
| 2 — Vault | Plugin role (scope = group) → policy → token path | `ask123` → `ask123-pull` → `artifactory/token/ask123` |
| 3 — Kubernetes | SA → K8s auth role → ESO → pull secret → pod | `workload-sa` → `ask123-workload` → `ExternalSecret` → `artifactory-pull` |

**Open question (not lab-tested):** Shared Vault across multiple clusters with namespace-scoped policies — see customer notes in `internal/customer-requirements.md`.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| JFrog Cloud tenant | Set `JFROG_URL` in `.env` (e.g. `https://YOUR-TENANT.jfrog.io`) |
| Admin-scoped access token | `applied-permissions/admin`; store in `.env` as `JFROG_ACCESS_TOKEN` |
| JFrog CLI | `jf config add` with `--server-id` matching `JFROG_SERVER_ID` in `.env` |
| HashiCorp Vault CLI | v2.x |
| Docker | Build and pull images |
| Go + GoReleaser | Build plugin from `vault-plugin-secrets-artifactory` |
| Local Kubernetes | Rancher Desktop k3s; `kubectl` working |
| Tools | `curl`, `jq`, `helm` (Phase 3) |

```bash
cp .env.example .env   # fill in secrets; never commit .env (VAULT_TOKEN=root is dev-only)
```

---

## Provisioned resources (inventory)

### JFrog Platform — ASK123 (project `ask123`)

| Resource | Name / key | Purpose |
|----------|------------|---------|
| Project | `ask123` | Dedicated JFrog Project for CMDB app ASK123 |
| Dev Docker repo | `ask123-docker-dev-local` | Negative isolation tests only |
| Prod Docker repo | `ask123-docker-prod-local` | ASK123 production pulls |
| Group | `AZU_ARTIFACTORY_ASK123` | CMDB app ASK123 RBAC |
| Permission target | `ask123-docker-prod-pull` | READ on prod repo for ASK123 group only |
| Docker image | `ask-123-demo:1.0.0` | Pull verification image |

### Vault — ASK123

| Resource | Name | Purpose |
|----------|------|---------|
| Secrets engine | `artifactory/` | Plugin mount (dynamic credentials — not KV) |
| Admin config | `artifactory/config/admin` | Artifactory URL + bootstrap token |
| Plugin role | `ask123` | Scope `applied-permissions/groups:AZU_ARTIFACTORY_ASK123` |
| Policy | `ask123-pull` | Allows `read` on `artifactory/token/ask123` |
| Kubernetes auth | `auth/kubernetes` | SA JWT → policy `ask123-pull` |
| K8s auth role | `ask123-workload` | Binds `workload-sa` in `ask123-ns` |

### Kubernetes — ASK123

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| Namespace | `ask123-ns` | ASK123 workloads |
| Service account | `workload-sa` | Workload identity for Vault K8s auth |
| Service account | `kube-system/vault-auth` | Vault token reviewer (`system:auth-delegator`) |
| VaultDynamicSecret | `ask123-ns` | ESO generator: GET `artifactory/token/ask123` |
| ExternalSecret | `ask123-ns` | Syncs `artifactory-pull` (`kubernetes.io/dockerconfigjson`) |
| ESO operator | `external-secrets` | Helm-installed |
| Pod | `lab-demo-eso` | Pull verification via ESO-synced secret |

### ASK456 (Phase 4 — project `ask456`, multi-app isolation proof)

| Resource | Name / key | Purpose |
|----------|------------|---------|
| Project | `ask456` | Dedicated JFrog Project for CMDB app ASK456 |
| Dev Docker repo | `ask456-docker-dev-local` | Negative isolation tests (optional) |
| Prod Docker repo | `ask456-docker-prod-local` | ASK456 production pulls |
| Group | `AZU_ARTIFACTORY_ASK456` | CMDB app ASK456 RBAC |
| Permission target | `ask456-docker-prod-pull` | READ on ASK456 prod repo only |
| Docker image | `ask-456-demo:1.0.0` | ASK456 prod image |
| Vault plugin role | `ask456` | Scope `applied-permissions/groups:AZU_ARTIFACTORY_ASK456` |
| Vault policy | `ask456-pull` | Allows `read` on `artifactory/token/ask456` |
| Namespace | `ask456-ns` | ASK456 workloads |
| K8s auth role | `ask456-workload` | Binds `workload-sa` in ASK456 namespace |

Entity diagram: [visual-architecture.md#entity-relationship-diagram](visual-architecture.md#entity-relationship-diagram).

---

## Setup order

Complete steps in this order. Later steps depend on earlier ones.

### Phase 0 — Plugin and Vault bootstrap

**Where:** `vault-plugin-secrets-artifactory` repo + `vault-artifactory-lab`

```bash
cd ../vault-plugin-secrets-artifactory
make build

cd ../vault-artifactory-lab
source .env
./scripts/setup-vault.sh
```

**Validate:**

```bash
vault secrets list | grep artifactory
vault read artifactory/config/admin
```

### Phase 1 — Artifactory RBAC + Vault role (ASK123, project `ask123`)

**Order matters:** project → group → dev+prod repos → permission target → images → Vault role.

#### 1a. Artifactory provisioning (automated)

```bash
./scripts/setup-phase1-artifactory.sh
```

Creates JFrog project `ask123`, group `AZU_ARTIFACTORY_ASK123`, repos `ask123-docker-dev-local` and `ask123-docker-prod-local`, permission `ask123-docker-prod-pull`, and publishes `ask-123-demo:1.0.0` to both repos.

Verify:

```bash
jf api /access/api/v2/groups/AZU_ARTIFACTORY_ASK123 --server-id "${JFROG_SERVER_ID}"
jf api /access/api/v2/permissions/ask123-docker-prod-pull --server-id "${JFROG_SERVER_ID}"
docker pull YOUR-TENANT.jfrog.io/ask123-docker-prod-local/ask-123-demo:1.0.0
```

#### 1b. Vault role and policy

```bash
./scripts/setup-phase1-vault.sh
```

**Validate:**

```bash
vault read artifactory/roles/ask123
# scope must be applied-permissions/groups:AZU_ARTIFACTORY_ASK123

RESP=$(vault read -format=json artifactory/token/ask123)
echo "$RESP" | jq -r '.data.scope, .data.username'
```

**Critical:** Use a single `vault read -format=json` per test. Username and `access_token` must come from the same response.

#### 1c. Optional — Layer 1 isolation (host Docker)

Validates Artifactory RBAC without Kubernetes:

```bash
./scripts/demo-isolation.sh
```

**Expected:** prod pull PASS; dev repo `ask123-docker-dev-local` denied.

### Phase 2 — Vault Kubernetes auth

Requires Phase 1. Vault dev server on **host**; cluster API at `https://127.0.0.1:6443` (Rancher Desktop).

```bash
./scripts/setup-kubernetes-auth.sh
./scripts/demo-kubernetes-auth.sh
```

Creates `workload-sa`, `kube-system/vault-auth`, `auth/kubernetes`, role `ask123-workload`.

| Component | Value |
|-----------|-------|
| Namespace | `ask123-ns` |
| Workload SA | `workload-sa` |
| Vault auth role | `ask123-workload` |
| Vault policy | `ask123-pull` |
| Token reviewer SA | `kube-system/vault-auth` |

**Expected:**

- PASS: SA JWT → Vault login (policy `ask123-pull`)
- PASS: `artifactory/token/ask123` readable without root token
- PASS: `artifactory/config/admin` denied

**Troubleshooting:**

| Symptom | Fix |
|---------|-----|
| `permission denied` on login | Check SA name/namespace vs `vault read auth/kubernetes/role/ask123-workload` |
| Vault cannot reach API | Re-run setup; confirm `https://127.0.0.1:6443` from host |
| Login OK, token read denied | Re-run `./scripts/setup-phase1-vault.sh` |
| Reviewer JWT expired | Re-run `./scripts/setup-kubernetes-auth.sh` |

### Phase 3 — External Secrets Operator

Requires Phases 1 + 2. Vault reachable from cluster at `http://host.docker.internal:8200`.

```bash
./scripts/setup-eso.sh
./scripts/demo-eso.sh
```

ESO uses **VaultDynamicSecret** (GET `artifactory/token/ask123`) + **ExternalSecret** — not KV `SecretStore.remoteRef`. The `artifactory/` mount is a plugin secrets engine (dynamic credentials), not Vault KV.

| Component | Value |
|-----------|-------|
| ESO namespace | `external-secrets` |
| Workload namespace | `ask123-ns` |
| VaultDynamicSecret | `artifactory-ask123-token` |
| ExternalSecret | `artifactory-pull` |
| Test pod | `lab-demo-eso` |

**Expected (primary end-to-end validation):**

```
PASS: ExternalSecret artifactory-pull is Ready
PASS: pod pulled and ran prod image
Successful Image Pull from Artifactory
```

**Customer mapping:**

| Question | Lab answer |
|----------|------------|
| SA → Vault policy? | `workload-sa` → `ask123-workload` → `ask123-pull` |
| ESO integration? | **VaultDynamicSecret** + K8s auth (not KV SecretStore) |
| Token path? | **`artifactory/token/ask123`** — not `artifactory/roles/…` |
| Deployment pull? | `imagePullSecrets` → ESO-synced `artifactory-pull` |

**Troubleshooting:**

| Symptom | Fix |
|---------|-----|
| ExternalSecret `SecretSyncedError` | Confirm Vault reachable: `http://host.docker.internal:8200/v1/sys/health` from a pod |
| `Token failed verification: revoked` | Refresh plugin admin: `jf atc --grant-admin …` then `vault write artifactory/config/admin …` |
| Vault restart wiped config | Dev server is in-memory; re-run Phases 0–3 |
| `unknown field … audiences` | Not supported on VaultDynamicSecret CRD — removed from lab manifest |

### Phase 4 — Multi-app isolation (ASK456, project `ask456`)

Optional lab proof that two CMDB apps in **separate JFrog Projects** cannot cross-pull.

```bash
./scripts/setup-phase4-artifactory.sh
./scripts/setup-phase4-vault.sh
./scripts/demo-isolation-multi-app.sh
```

**Expected:**

- ASK123 token pulls own prod repo; denied on ASK456 prod repo
- ASK456 token pulls own prod repo; denied on ASK123 prod repo
- ASK456 SA Vault token reads `artifactory/token/ask456` only

---

## Validation checklist

Run after full setup. Primary success criteria are checks **9–10** (K8s auth + ESO).

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Vault plugin mounted | `vault secrets list` | `artifactory/` |
| 2 | Admin config | `vault read artifactory/config/admin` | URL + token metadata |
| 3 | ASK123 group | `jf api /access/api/v2/groups/AZU_ARTIFACTORY_ASK123 --server-id "${JFROG_SERVER_ID}"` | 200 |
| 4 | Permission target | `jf api /access/api/v2/permissions/ask123-docker-prod-pull --server-id "${JFROG_SERVER_ID}"` | READ on prod repo |
| 5 | Prod image exists | `docker pull …/ask123-docker-prod-local/ask-123-demo:1.0.0` | tag `1.0.0` |
| 6 | Vault role scope | `vault read artifactory/roles/ask123` | `AZU_ARTIFACTORY_ASK123` in scope |
| 7 | Layer 1 isolation (optional) | `./scripts/demo-isolation.sh` | prod PASS, dev denied |
| 8 | K8s auth login | `./scripts/demo-kubernetes-auth.sh` | SA JWT → Vault token → Artifactory token |
| 9 | **ESO sync (primary)** | `./scripts/demo-eso.sh` | ExternalSecret Ready; pod `lab-demo-eso` Running |
| 10 | Multi-app isolation (optional) | `./scripts/demo-isolation-multi-app.sh` | Cross-app prod pulls denied |

Quick health ping:

```bash
RESP=$(vault read -format=json artifactory/token/ask123)
curl -sf -H "Authorization: Bearer $(echo "$RESP" | jq -r '.data.access_token')" \
  "${JFROG_URL}/artifactory/api/system/ping" && echo "ping OK"
```

---

## API tooling notes

| Task | Tool | Example |
|------|------|---------|
| Access API (groups, permissions) | `jf api` | `jf api /access/api/v2/groups/...` |
| Artifactory Docker API | `jf rt curl` | `jf rt curl -XGET "/api/docker/..."` |
| Docker image promote | `jf rt docker-promote` | dev → prod copy |

Do **not** use `jf rt curl` for Access API paths — returns 404 for `/access/api/...`.

JFrog doc corrections (URL format, permission API): [appendix/jfrog-doc-corrections.md](appendix/jfrog-doc-corrections.md).
