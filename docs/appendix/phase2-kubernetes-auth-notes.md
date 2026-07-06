# Phase 2 — operational notes (supplementary)

Operational detail for Vault Kubernetes auth in this lab. **Canonical runbook:** [../setup-and-validation.md](../setup-and-validation.md). **Core guide:** [phase2-kubernetes-auth.md](phase2-kubernetes-auth.md).

---

## Environment variables

Scripts read these from `.env` (see `.env.example`). Defaults match the lab Rancher Desktop layout.

| Variable | Default | Used by | Purpose |
|----------|---------|---------|---------|
| `K8S_NAMESPACE` | `vaultdemo-ns` | setup, demo | Workload namespace |
| `K8S_WORKLOAD_SA` | `workload-sa` | setup, demo | SA bound to Vault K8s auth role |
| `K8S_AUTH_ROLE` | `vaultdemo-workload` | setup, demo | Vault `auth/kubernetes/role/…` name |
| `VAULT_K8S_AUTH_PATH` | `kubernetes` | setup, demo | Vault auth mount path |
| `K8S_VAULT_AUTH_SA` | `vault-auth` | setup | Token reviewer SA name |
| `K8S_VAULT_AUTH_NS` | `kube-system` | setup | Namespace for reviewer SA |
| `K8S_VAULT_AUTH_BINDING` | `vault-auth-delegator` | setup, cleanup | ClusterRoleBinding name |
| `K8S_REVIEWER_TOKEN_DURATION` | `87600h` | setup | Reviewer JWT lifetime (~10 years; lab only) |
| `K8S_WORKLOAD_TOKEN_DURATION` | `1h` | demo | SA JWT lifetime for validation |

Vault connection (`VAULT_ADDR`, `VAULT_TOKEN`) is shared with other lab scripts.

---

## Vault Kubernetes auth role settings

Written by `setup-kubernetes-auth.sh`:

| Setting | Value |
|---------|-------|
| `bound_service_account_names` | `workload-sa` |
| `bound_service_account_namespaces` | `vaultdemo-ns` |
| `policies` | `vaultdemo-ask123-pull` |
| `ttl` | `1h` |
| `max_ttl` | `3h` |

Verify: `vault read auth/kubernetes/role/vaultdemo-workload`

---

## Kubernetes RBAC created

| Resource | Name | Purpose |
|----------|------|---------|
| ServiceAccount | `vaultdemo-ns/workload-sa` | Workload identity for auth login |
| ServiceAccount | `kube-system/vault-auth` | JWT presented to K8s API for TokenReview |
| ClusterRoleBinding | `vault-auth-delegator` | Grants `system:auth-delegator` to `vault-auth` |

---

## Validation scope

| What `demo-kubernetes-auth.sh` proves | What it does **not** prove |
|---------------------------------------|----------------------------|
| SA JWT minted via `kubectl create token` | Pod inside cluster calling Vault over the network |
| Vault Kubernetes auth login from **host** | ESO SecretStore sync (Phase 3) |
| Workload Vault token reads `artifactory/token/vaultdemo` | Cold registry pull from cluster |
| Admin path denied for workload token | |

The demo simulates what ESO will do (mint SA JWT → Vault login) but runs on the Mac where `kubectl` and `vault` CLIs execute. In-cluster validation (pod with `serviceAccountName: workload-sa` calling Vault) is optional hardening, not required for Phase 2 completion.

---

## Idempotent re-runs

`setup-kubernetes-auth.sh` is safe to re-run:

- Namespace and service accounts: `kubectl apply` with `--dry-run=client`
- ClusterRoleBinding: created only if missing
- Kubernetes auth: enables mount only if absent; **always** refreshes `auth/kubernetes/config` (new reviewer JWT)
- Auth role: overwritten each run

Re-run setup after Vault restart, reviewer JWT expiry, or cluster credential changes.

---

## Tool requirements

| Script | Requires |
|--------|----------|
| `setup-kubernetes-auth.sh` | `kubectl`, `vault`, `jq` |
| `demo-kubernetes-auth.sh` | `kubectl`, `vault`, `jq` |

---

## Expected warnings and policy behavior

### Audience warning on role create

Vault may print:

```
Role vaultdemo-workload does not have an audience configured…
```

Harmless for this lab. Audiences add optional JWT claim checks; not required for local k3s.

### `default` policy on login token

Successful login may show policies: `default,vaultdemo-ask123-pull`.

- `vaultdemo-ask123-pull` — grants `artifactory/token/vaultdemo` (intentional)
- `default` — Vault’s built-in policy on all tokens unless disabled; does not grant Artifactory paths in this lab

---

## Validated outcome (2026-06-22)

Environment: Rancher Desktop k3s (`127.0.0.1:6443`), Vault dev on host (`127.0.0.1:8200`).

```
PASS: SA JWT issued
PASS: Vault login succeeded (policies: default,vaultdemo-ask123-pull)
PASS: policy vaultdemo-ask123-pull attached
PASS: Artifactory token scope includes AZU_ARTIFACTORY_ASK123
PASS: access_token issued
PASS: artifactory/config/admin denied for workload token
```

Re-validate: `./scripts/demo-kubernetes-auth.sh`

---

## Related

- [phase2-kubernetes-auth.md](phase2-kubernetes-auth.md) — core guide
- [setup-and-validation.md](setup-and-validation.md) — full lab order and checklist
