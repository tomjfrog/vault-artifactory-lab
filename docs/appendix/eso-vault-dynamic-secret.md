# Phase 3 — ESO technical notes (supplementary)

ESO integration with the **artifactory secrets engine** (non-KV). **Runtime sequence diagram:** [../visual-architecture.md#runtime-sequence-automated-eso-path](../visual-architecture.md#runtime-sequence-automated-eso-path).

Canonical runbook: [../setup-and-validation.md](../setup-and-validation.md).

---

## Vault engine types (relevant to ESO)

| Mount | Type | Example path | Stores static data? |
|-------|------|--------------|---------------------|
| `secret/` | KV v2 | `secret/data/myapp/config` | Yes |
| `artifactory/` | **Plugin secrets engine** | `artifactory/token/vaultdemo` | No — **issues** Artifactory tokens on read |

The plugin is registered as a Vault **secrets engine** (`vault secrets enable -path=artifactory ...`). Paths under `artifactory/` are implemented by [vault-plugin-secrets-artifactory](https://github.com/jfrog/vault-plugin-secrets-artifactory), not by JFrog Artifactory itself.

`vault read artifactory/token/vaultdemo` ≈ HTTP `GET /v1/artifactory/token/vaultdemo` → JSON `data` with `username`, `access_token`, `scope`, lease fields.

---

## Why the standard ESO Vault SecretStore is insufficient

Many ESO + Vault examples assume KV:

```yaml
# Typical KV pattern — does NOT apply to artifactory/token paths
apiVersion: external-secrets.io/v1
kind: SecretStore
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"      # KV mount
      version: "v2"
```

ESO documentation ([HashiCorp Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/)):

> The KV Secrets Engine is the only one supported by this provider. For other secrets engines, please refer to the Vault Generator.

So `remoteRef.key: artifactory/token/vaultdemo` on a KV-configured `SecretStore` will **not** work — there is no KV secret at that path; the artifactory engine lives on a different mount with different API semantics.

**This gap was not documented in early lab Phase 3 outlines** (which described `SecretStore` + `remoteRef` only). Phase 3 implementation will use the **generator** path below.

---

## Planned pattern: VaultDynamicSecret + ExternalSecret

[VaultDynamicSecret](https://external-secrets.io/latest/api/generator/vault/) calls arbitrary Vault API paths with GET/POST. Kubernetes auth on the generator `provider` reuses Phase 2 (`workload-sa`, role `vaultdemo-workload`).

**Sketch (implemented in `k8s/eso/`):**

```yaml
apiVersion: generators.external-secrets.io/v1alpha1
kind: VaultDynamicSecret
metadata:
  name: artifactory-vaultdemo-token
  namespace: vaultdemo-ns
spec:
  path: "/artifactory/token/vaultdemo"
  method: "GET"
  resultType: "Data"
  provider:
    server: "http://host.docker.internal:8200"
    version: "v1"
    auth:
      kubernetes:
        mountPath: "kubernetes"
        role: "vaultdemo-workload"
        serviceAccountRef:
          name: workload-sa
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: artifactory-pull
  namespace: vaultdemo-ns
spec:
  refreshInterval: 1h
  target:
    name: artifactory-pull
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      engineVersion: v2
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "YOUR-TENANT.jfrog.io": {
                "username": "{{ .username }}",
                "password": "{{ .access_token }}",
                "auth": "{{ printf "%s:%s" .username .access_token | b64enc }}"
              }
            }
          }
  dataFrom:
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: VaultDynamicSecret
          name: artifactory-vaultdemo-token
```

Field names `username` and `access_token` match the plugin’s `vault read` output (not `password`).

---

## Validated outcome (2026-07-06)

```
PASS: ExternalSecret artifactory-pull is Ready
PASS: secret type is kubernetes.io/dockerconfigjson
PASS: pod lab-demo-eso — Successful Image Pull from Artifactory
```

Re-validate: `./scripts/demo-eso.sh`

---

## `remoteRef.key` vs plugin role path

| Vault path | Purpose | Use in ESO? |
|------------|---------|-------------|
| `artifactory/roles/vaultdemo` | Role **configuration** (scope, TTL) | No — not credentials |
| `artifactory/token/vaultdemo` | **Issue** Artifactory registry token | **Yes** — generator `path` or equivalent |

Customer confusion (`remoteRef` → role vs token) is understandable: the **plugin role name** (`vaultdemo`) appears in the **token path** (`artifactory/token/vaultdemo`), but the path prefix is `token/`, not `roles/`.

With VaultDynamicSecret, the integration point is `spec.path` on the generator, not `remoteRef.key` on a KV `SecretStore`.

---

## Kubernetes auth (Phase 2 — already done)

ESO does not replace Kubernetes auth — it **uses** it:

1. ESO controller reads `workload-sa` token (via `serviceAccountRef` on the generator).
2. `auth/kubernetes/login` with role `vaultdemo-workload`.
3. Vault token with policy `vaultdemo-ask123-pull` only.
4. Generator calls `artifactory/token/vaultdemo`.

Separate customer pattern: dedicated `external-secrets-sa` in `external-secrets` namespace with its own Vault role. The lab binds **`workload-sa` in `vaultdemo-ns`** so the identity matches the workload namespace (closer to per-namespace team ownership).

---

## Alternatives (not planned for lab)

| Approach | Notes |
|----------|-------|
| Mirror tokens into KV | Extra moving parts; duplicates leases |
| Custom ESO provider | Out of scope |
| Manual / CI `vault read` | Phase 1d — already proven |
| Push static creds to KV | Defeats dynamic token model |

---

## References

- [ESO — HashiCorp Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/) (KV only)
- [ESO — VaultDynamicSecret generator](https://external-secrets.io/latest/api/generator/vault/)
- [ESO — dockerconfigjson templates](https://external-secrets.io/latest/guides/common-k8s-secret-types/)
- [JFrog HashiCorp integrations](https://docs.jfrog.com/integrations/docs/hashicorp-integrations)
- Plugin README — [vault-plugin-secrets-artifactory](https://github.com/jfrog/vault-plugin-secrets-artifactory)
