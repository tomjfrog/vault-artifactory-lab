# Lab Docker images

Two minimal Alpine images verify Docker pull access from Artifactory after obtaining a Vault-issued token. Each image maps to one CMDB application.

| CMDB app | Dockerfile | Image name | Prod repo | Runtime message |
|----------|------------|------------|-----------|-----------------|
| **ASK123** (Phase 1) | `Dockerfile.ask123` | `lab-demo` | `vaultdemo-docker-prod-local` | `Successful Image Pull from Artifactory` |
| **ASK456** (Phase 4) | `Dockerfile.ask456` | `lab-demo-ask456` | `vaultdemo-docker-ask456-prod-local` | `Successful Image Pull from Artifactory (ASK456)` |

ASK123 also uses dev repo `vaultdemo-docker-local` for negative isolation tests (token must **not** pull from dev).

Runbook: [docs/setup-and-validation.md](../docs/setup-and-validation.md). Visual map: [docs/visual-architecture.md](../docs/visual-architecture.md).

---

## ASK123-only assets (first image)

### Docker build

| File | Purpose |
|------|---------|
| `assets/Dockerfile.ask123` | Image definition (Alpine 3.21) |
| `assets/publish.sh` | Build + push; defaults to `lab-demo` → `vaultdemo-docker-local` |

```bash
./assets/publish.sh
DOCKER_REPO=vaultdemo-docker-prod-local ./assets/publish.sh
```

### Vault, scripts, K8s manifests

| File | Purpose |
|------|---------|
| `policies/vaultdemo-ask123-pull.hcl` | Allows read of `artifactory/token/vaultdemo` |
| `scripts/setup-phase1-vault.sh` | Policy + plugin role `vaultdemo` |
| `scripts/setup-kubernetes-auth.sh` | K8s auth in `vaultdemo-ns` |
| `scripts/setup-eso.sh` | ESO + VaultDynamicSecret + ExternalSecret |
| `scripts/demo-isolation.sh` | Optional Layer 1 RBAC check (host Docker) |
| `scripts/demo-kubernetes-auth.sh` | Layer 2: SA → Vault |
| `scripts/demo-eso.sh` | **Primary** end-to-end validation |
| `k8s/eso/vault-dynamic-secret.yaml` | Generator: GET `artifactory/token/vaultdemo` |
| `k8s/eso/external-secret.yaml` | Syncs `artifactory-pull` |

---

## ASK456-only assets (second image)

| File | Purpose |
|------|---------|
| `assets/Dockerfile.ask456` | Image definition |
| `policies/vaultdemo-ask456-pull.hcl` | Allows read of `artifactory/token/vaultdemo-ask456` |
| `scripts/setup-phase4-artifactory.sh` | Group, repo, permission, build + push |
| `scripts/setup-phase4-vault.sh` | Role, policy, K8s auth in `vaultdemo-ask456-ns` |
| `scripts/demo-isolation-multi-app.sh` | Cross-app isolation (both apps) |

---

## Shared assets

| File | Purpose |
|------|---------|
| `scripts/setup-vault.sh` | Vault dev server + plugin mount |
| `.env.example` | Defaults to ASK123; Phase 4 vars prefixed `ASK456_*` |

---

## Pull and run (after Vault token issued)

```bash
docker login YOUR-TENANT.jfrog.io -u <username> -p <vault-issued-token>
docker pull YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/lab-demo:1.0.0
docker run --rm YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/lab-demo:1.0.0
```

Expected: `Successful Image Pull from Artifactory`
