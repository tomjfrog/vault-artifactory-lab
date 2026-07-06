# Lab Docker images

Two minimal Alpine images verify Docker pull access from Artifactory after obtaining a Vault-issued token. Each image maps to one CMDB application in its **own JFrog Project**.

| CMDB app | JFrog project | Dockerfile | Image name | Dev repo | Prod repo |
|----------|---------------|------------|------------|----------|-----------|
| **ASK123** | `ask123` | `Dockerfile.ask123` | `ask-123-demo` | `ask123-docker-dev-local` | `ask123-docker-prod-local` |
| **ASK456** | `ask456` | `Dockerfile.ask456` | `ask-456-demo` | `ask456-docker-dev-local` | `ask456-docker-prod-local` |

Runbook: [docs/setup-and-validation.md](../docs/setup-and-validation.md). Visual map: [docs/visual-architecture.md](../docs/visual-architecture.md).

---

## ASK123-only assets (first app)

### Docker build

| File | Purpose |
|------|---------|
| `assets/Dockerfile.ask123` | Image definition (Alpine 3.21) |
| `assets/publish.sh` | Build + push to `ask123-docker-dev-local` |
| `scripts/setup-phase1-artifactory.sh` | Full ASK123 Artifactory provisioning |

```bash
./scripts/setup-phase1-artifactory.sh
# or dev-only publish:
./assets/publish.sh
```

### Vault, scripts, K8s manifests

| File | Purpose |
|------|---------|
| `policies/ask123-pull.hcl` | Allows read of `artifactory/token/ask123` |
| `scripts/setup-phase1-vault.sh` | Policy + plugin role `ask123` |
| `scripts/setup-kubernetes-auth.sh` | K8s auth in `ask123-ns` |
| `scripts/setup-eso.sh` | ESO + VaultDynamicSecret + ExternalSecret |
| `scripts/demo-isolation.sh` | Optional Layer 1 RBAC check (host Docker) |
| `scripts/demo-kubernetes-auth.sh` | Layer 2: SA → Vault |
| `scripts/demo-eso.sh` | **Primary** end-to-end validation |
| `k8s/eso/vault-dynamic-secret.yaml` | Generator: GET `artifactory/token/ask123` |
| `k8s/eso/external-secret.yaml` | Syncs `artifactory-pull` |

---

## ASK456-only assets (second app)

| File | Purpose |
|------|---------|
| `assets/Dockerfile.ask456` | Image definition |
| `policies/ask456-pull.hcl` | Allows read of `artifactory/token/ask456` |
| `scripts/setup-phase4-artifactory.sh` | Project, repos, group, permission, build + push |
| `scripts/setup-phase4-vault.sh` | Role, policy, K8s auth in `ask456-ns` |
| `scripts/demo-isolation-multi-app.sh` | Cross-app isolation (both apps) |

---

## Shared assets

| File | Purpose |
|------|---------|
| `scripts/setup-vault.sh` | Vault dev server + plugin mount |
| `.env.example` | ASK123 and ASK456 variables |

---

## Pull and run (after Vault token issued)

```bash
docker login YOUR-TENANT.jfrog.io -u <username> -p <vault-issued-token>
docker pull YOUR-TENANT.jfrog.io/ask123-docker-prod-local/ask-123-demo:1.0.0
docker run --rm YOUR-TENANT.jfrog.io/ask123-docker-prod-local/ask-123-demo:1.0.0
```

Expected: `Successful Image Pull from Artifactory (ASK123 ask-123-demo)`
