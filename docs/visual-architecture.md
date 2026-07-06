# Visual architecture (Mermaid)

Visual reference for the Vault ↔ Artifactory lab: **entity relationships**, **setup order**, and **runtime flows**.

Validated on JFrog Cloud, local Vault dev, Rancher Desktop k3s, Phases 0–4.

| Diagram | Use when |
|---------|----------|
| [Entity relationship](#entity-relationship-diagram) | Understanding *what connects to what* (CMDB → group → repo → Vault → K8s) |
| [Setup sequence](#setup-order-sequence-diagram) | Provisioning a new app or reproducing the lab |
| [Runtime ESO sequence](#runtime-sequence-automated-eso-path) | Explaining the automated pull-credential chain |
| [Runtime manual sequence](#appendix-break-glass-manual-pull) | Debug only — operator-held root token |
| [Multi-app isolation](#multi-app-isolation) | Why ASK123 cannot pull ASK456 (and vice versa) |

Related: [setup-and-validation.md](setup-and-validation.md), [architecture.md](architecture.md), [appendix/](appendix/).

---

## Key findings (lab-validated)

| Finding | Implication |
|---------|-------------|
| `artifactory/` is a **plugin secrets engine** | Dynamic token issue on read — **not** Vault KV |
| ESO Vault **SecretStore** is KV-only | Use **VaultDynamicSecret** + `ExternalSecret.dataFrom.generatorRef` for `artifactory/token/…` |
| Token path vs role path | **`artifactory/token/vaultdemo`** issues credentials; **`artifactory/roles/vaultdemo`** is config only |
| One `vault read` per Docker login | Username + `access_token` must come from the **same** response |
| Phase 1 scope | `setup-phase1-vault.sh` derives scope from `ASK_ID` |
| Vault from cluster | `http://host.docker.internal:8200` (Rancher Desktop) |
| Permission target create | `POST /access/api/v2/permissions` with `name` in body (not `POST …/permissions/{name}`) |
| Per-app isolation | Separate group + permission target + prod repo + Vault role + policy + K8s auth role |

---

## Entity relationship diagram

Shows **one CMDB application** (pattern repeats for ASK123 and ASK456). Solid lines are direct bindings; dashed lines are runtime/issue flows.

```mermaid
erDiagram
    CMDB_APPLICATION ||--|| ARTIFACTORY_GROUP : "CMDB ID maps to"
    ARTIFACTORY_GROUP ||--o| PERMISSION_TARGET : "READ via"
    PERMISSION_TARGET }o--|| PROD_DOCKER_REPO : "scopes access to"
    PROD_DOCKER_REPO ||--o{ DOCKER_IMAGE : "stores"

    CMDB_APPLICATION ||--|| VAULT_PLUGIN_ROLE : "1:1 lab role"
    VAULT_PLUGIN_ROLE ||--|| ARTIFACTORY_GROUP : "scope applied-permissions/groups"
    VAULT_PLUGIN_ROLE ||--|| VAULT_TOKEN_PATH : "read issues token"
    VAULT_POLICY ||--|| VAULT_TOKEN_PATH : "allows read"

    K8S_NAMESPACE ||--|| K8S_SERVICE_ACCOUNT : "contains"
    K8S_SERVICE_ACCOUNT ||--|| VAULT_K8S_AUTH_ROLE : "JWT authenticates as"
    VAULT_K8S_AUTH_ROLE ||--|| VAULT_POLICY : "grants"

    VAULT_TOKEN_PATH ||--|| VAULT_SECRETS_ENGINE : "path on mount"
    VAULT_SECRETS_ENGINE ||--o| JFROG_ACCESS_API : "POST token"
    JFROG_ACCESS_API ||--|| ARTIFACTORY_GROUP : "token inherits group perms"

    K8S_NAMESPACE ||--o| VAULT_DYNAMIC_SECRET : "ESO generator"
    VAULT_DYNAMIC_SECRET ||--|| VAULT_TOKEN_PATH : "GET"
    VAULT_DYNAMIC_SECRET ||--|| K8S_SERVICE_ACCOUNT : "uses SA for K8s auth"
    EXTERNAL_SECRET ||--|| VAULT_DYNAMIC_SECRET : "dataFrom generatorRef"
    EXTERNAL_SECRET ||--|| K8S_PULL_SECRET : "syncs"
    K8S_PULL_SECRET ||--o| K8S_POD : "imagePullSecrets"

    CMDB_APPLICATION {
        string cmdb_id "ASK123 or ASK456"
        string jfrog_project "vaultdemo"
    }

    ARTIFACTORY_GROUP {
        string name "AZU_ARTIFACTORY_ASK123"
    }

    PERMISSION_TARGET {
        string name "vaultdemo-ask123-prod-pull"
        string permission "READ"
    }

    PROD_DOCKER_REPO {
        string key "vaultdemo-docker-prod-local"
        string env "PROD"
    }

    DOCKER_IMAGE {
        string name "lab-demo:1.0.0"
    }

    VAULT_SECRETS_ENGINE {
        string mount "artifactory"
        string type "plugin not KV"
    }

    VAULT_PLUGIN_ROLE {
        string name "vaultdemo"
        string scope "applied-permissions/groups:..."
    }

    VAULT_TOKEN_PATH {
        string path "artifactory/token/vaultdemo"
    }

    VAULT_POLICY {
        string name "vaultdemo-ask123-pull"
    }

    VAULT_K8S_AUTH_ROLE {
        string name "vaultdemo-workload"
        string mount "auth/kubernetes"
    }

    K8S_NAMESPACE {
        string name "vaultdemo-ns"
    }

    K8S_SERVICE_ACCOUNT {
        string name "workload-sa"
    }

    VAULT_DYNAMIC_SECRET {
        string name "artifactory-vaultdemo-token"
    }

    EXTERNAL_SECRET {
        string name "artifactory-pull"
        string refresh "1h"
    }

    K8S_PULL_SECRET {
        string type "kubernetes.io/dockerconfigjson"
    }

    K8S_POD {
        string name "lab-demo-eso"
    }

    JFROG_ACCESS_API {
        string endpoint "POST /access/api/v1/tokens"
    }
```

### Lab instances (two apps)

```mermaid
flowchart TB
    subgraph project["JFrog Project vaultdemo"]
        subgraph ask123["CMDB ASK123"]
            G1["Group AZU_ARTIFACTORY_ASK123"]
            P1["Perm vaultdemo-ask123-prod-pull"]
            R1["Repo vaultdemo-docker-prod-local"]
            I1["Image lab-demo:1.0.0"]
            G1 --> P1 --> R1 --> I1
        end
        subgraph ask456["CMDB ASK456"]
            G2["Group AZU_ARTIFACTORY_ASK456"]
            P2["Perm vaultdemo-ask456-prod-pull"]
            R2["Repo vaultdemo-docker-ask456-prod-local"]
            I2["Image lab-demo-ask456:1.0.0"]
            G2 --> P2 --> R2 --> I2
        end
        DEV["Dev repo vaultdemo-docker-local"]
    end

    subgraph vault["Vault dev"]
        VR1["role vaultdemo"]
        VR2["role vaultdemo-ask456"]
        VP1["policy vaultdemo-ask123-pull"]
        VP2["policy vaultdemo-ask456-pull"]
        VR1 --> VP1
        VR2 --> VP2
    end

    subgraph k8s["Kubernetes"]
        NS1["vaultdemo-ns"]
        NS2["vaultdemo-ask456-ns"]
        ESO["External Secrets Operator"]
    end

    VR1 -.->|scope| G1
    VR2 -.->|scope| G2
    NS1 --> ESO
    ESO -.->|VaultDynamicSecret| VR1
```

---

## Setup order sequence diagram

Order of operations to provision **one app** (ASK123). Repeat Artifactory + Vault + K8s auth blocks for ASK456 (Phase 4). ESO is optional per namespace (Phase 3, ASK123 only in lab).

```mermaid
sequenceDiagram
    autonumber
    participant Op as Operator
    participant PluginRepo as vault-plugin-secrets-artifactory
    participant Vault
    participant JFrog as JFrog Platform
    participant K8s as Kubernetes
    participant ESO as External Secrets Operator

    rect rgb(240, 248, 255)
        Note over Op,Vault: Phase 0 — Plugin bootstrap
        Op->>PluginRepo: make build
        Op->>Vault: make start (dev server)
        Op->>Vault: register plugin, enable artifactory/
        Op->>Vault: artifactory/config/admin (URL + admin token)
    end

    rect rgb(255, 250, 240)
        Note over Op,JFrog: Phase 1a — Artifactory RBAC (per CMDB app)
        Op->>JFrog: POST /access/api/v2/groups (AZU_ARTIFACTORY_ASK123)
        Op->>JFrog: Create prod Docker repo
        Op->>JFrog: POST /access/api/v2/permissions (READ on prod repo)
        Op->>JFrog: Publish lab-demo:1.0.0 to prod repo
    end

    rect rgb(240, 255, 240)
        Note over Op,Vault: Phase 1b — Vault role + policy
        Op->>Vault: policy write vaultdemo-ask123-pull
        Op->>Vault: write artifactory/roles/vaultdemo (scope = ASK123 group)
    end

    rect rgb(255, 240, 255)
        Note over Op,K8s: Phase 2 — Kubernetes auth
        Op->>K8s: namespace vaultdemo-ns, SA workload-sa
        Op->>K8s: SA vault-auth + auth-delegator (kube-system)
        Op->>Vault: enable auth/kubernetes, configure API + reviewer JWT
        Op->>Vault: role vaultdemo-workload → policy vaultdemo-ask123-pull
    end

    rect rgb(255, 255, 230)
        Note over Op,ESO: Phase 3 — ESO (ASK123 namespace)
        Op->>K8s: helm install external-secrets
        Op->>K8s: VaultDynamicSecret (GET artifactory/token/vaultdemo)
        Op->>K8s: ExternalSecret → artifactory-pull (dockerconfigjson)
    end

    rect rgb(230, 245, 255)
        Note over Op,K8s: Phase 4 — Second app (ASK456)
        Op->>JFrog: group + repo + permission for ASK456
        Op->>Vault: role vaultdemo-ask456 + policy
        Op->>K8s: namespace vaultdemo-ask456-ns + K8s auth role
    end

    rect rgb(245, 245, 245)
        Note over Op,K8s: Validation
        Op->>Op: demo-isolation.sh (ASK123 prod yes, dev no)
        Op->>Op: demo-kubernetes-auth.sh
        Op->>Op: demo-eso.sh
        Op->>Op: demo-isolation-multi-app.sh
    end
```

---

## Runtime sequence (automated ESO path)

Full **customer target** flow: no human `vault read`; ESO syncs pull secret before kubelet pulls.

```mermaid
sequenceDiagram
    autonumber
    participant ESO as External Secrets Operator
    participant K8sAPI as Kubernetes API
    participant Vault
    participant Plugin as artifactory engine
    participant Access as JFrog Access
    participant RT as Artifactory Registry
    participant Kubelet as kubelet

    Note over ESO: Triggered by ExternalSecret refreshInterval (1h)<br/>or initial reconcile

    ESO->>K8sAPI: Request SA token for workload-sa
    K8sAPI-->>ESO: ServiceAccount JWT

    ESO->>Vault: auth/kubernetes/login (role vaultdemo-workload, jwt)
    Vault->>K8sAPI: TokenReview (vault-auth SA)
    K8sAPI-->>Vault: SA identity confirmed
    Vault-->>ESO: Vault token (policy vaultdemo-ask123-pull)

    ESO->>Vault: GET /v1/artifactory/token/vaultdemo
    Vault->>Plugin: issue token (scope AZU_ARTIFACTORY_ASK123)
    Plugin->>Access: POST /access/api/v1/tokens
    Access-->>Plugin: username + access_token
    Plugin-->>ESO: data.username, data.access_token

    ESO->>ESO: Template kubernetes.io/dockerconfigjson
    ESO->>K8sAPI: Create/Update Secret artifactory-pull

    Note over Kubelet: Pod scheduled with imagePullSecrets

    Kubelet->>K8sAPI: Read Secret artifactory-pull
    Kubelet->>RT: docker pull vaultdemo-docker-prod-local/lab-demo:1.0.0
    RT->>RT: Check group AZU_ARTIFACTORY_ASK123 READ on repo
    RT-->>Kubelet: Image layers
    Kubelet-->>Kubelet: Start container
```

---

## Appendix: break-glass manual pull

Debug-only path: operator creates pull secret with Vault root token. **Not the customer path** — use Phase 3 ESO instead. Full procedure: [appendix/break-glass-manual-pull.md](appendix/break-glass-manual-pull.md).

## Runtime sequence (manual — debug only)

Same RBAC outcome without ESO — operator holds Vault root token.

```mermaid
sequenceDiagram
    autonumber
    participant Op as Operator
    participant Vault
    participant Plugin as artifactory engine
    participant Access as JFrog Access
    participant K8sAPI as Kubernetes API
    participant RT as Artifactory Registry
    participant Kubelet as kubelet

    Op->>Vault: vault read -format=json artifactory/token/vaultdemo
    Note over Op,Vault: Single read — username + access_token same response

    Vault->>Plugin: issue token
    Plugin->>Access: POST /access/api/v1/tokens
    Access-->>Plugin: scoped token (ASK123 group)
    Plugin-->>Op: username + access_token

    Op->>K8sAPI: kubectl create secret docker-registry artifactory-pull
    Op->>K8sAPI: kubectl run lab-demo (imagePullSecrets)

    Kubelet->>RT: docker pull (prod repo)
    RT-->>Kubelet: lab-demo:1.0.0
```

---

## Multi-app isolation

Cross-app denial is enforced at **three layers**: Artifactory permission targets, Vault policies, and scoped plugin tokens.

```mermaid
sequenceDiagram
    participant T123 as Token ASK123
    participant T456 as Token ASK456
    participant RT as Artifactory

    Note over T123: scope AZU_ARTIFACTORY_ASK123
    T123->>RT: pull vaultdemo-docker-prod-local/lab-demo
    RT-->>T123: OK
    T123->>RT: pull vaultdemo-docker-ask456-prod-local/lab-demo-ask456
    RT-->>T123: DENIED

    Note over T456: scope AZU_ARTIFACTORY_ASK456
    T456->>RT: pull vaultdemo-docker-ask456-prod-local/lab-demo-ask456
    RT-->>T456: OK
    T456->>RT: pull vaultdemo-docker-prod-local/lab-demo
    RT-->>T456: DENIED
```

```mermaid
flowchart LR
    subgraph vault_isolation["Vault policy boundary"]
        SA456["workload-sa<br/>vaultdemo-ask456-ns"]
        AR456["auth role<br/>vaultdemo-ask456-workload"]
        P456["policy<br/>vaultdemo-ask456-pull"]
        TP456["artifactory/token/vaultdemo-ask456"]
        SA456 --> AR456 --> P456 --> TP456
        TP123["artifactory/token/vaultdemo"]
        TP123 -.->|DENIED| P456
    end
```

---

## Three binding layers (customer model)

The customer scenario chains **three independent bindings**. The ER diagram above maps to this summary:

```mermaid
flowchart TB
    subgraph L1["Layer 1 — Artifactory RBAC"]
        CMDB1["CMDB ASK123"] --> G1["Group AZU_ARTIFACTORY_ASK123"]
        G1 --> PT1["Permission READ"]
        PT1 --> REPO1["Prod repo only"]
    end

    subgraph L2["Layer 2 — Vault"]
        CMDB1 --> VR1["Plugin role vaultdemo"]
        VR1 --> S1["scope = group"]
        VR1 --> PATH1["token path artifactory/token/vaultdemo"]
        POL1["Policy vaultdemo-ask123-pull"] --> PATH1
    end

    subgraph L3["Layer 3 — Kubernetes"]
        SA1["SA workload-sa"] --> KAUTH1["K8s auth role"]
        KAUTH1 --> POL1
        ESO1["ESO ExternalSecret"] --> SEC1["pull secret"]
        SEC1 --> POD1["Pod imagePullSecrets"]
    end

    PATH1 --> SEC1
```

---

## Script ↔ phase map

| Phase | Setup script | Validation script |
|-------|--------------|-------------------|
| 0 | `setup-vault.sh` / plugin `make setup` | `vault read artifactory/config/admin` |
| 1a–1e | Artifactory `jf api` / `publish.sh`, `setup-phase1-vault.sh` | `docker pull` prod, `vault read artifactory/roles/vaultdemo` |
| 1f | — | `demo-isolation.sh` (optional Layer 1) |
| 2 | `setup-kubernetes-auth.sh` | `demo-kubernetes-auth.sh` |
| 3 | `setup-eso.sh` | `demo-eso.sh` (primary) |
| 4 | `setup-phase4-artifactory.sh`, `setup-phase4-vault.sh` | `demo-isolation-multi-app.sh` |

---

## Related docs

- [setup-and-validation.md](setup-and-validation.md) — canonical runbook
- [appendix/eso-vault-dynamic-secret.md](appendix/eso-vault-dynamic-secret.md) — VaultDynamicSecret vs KV SecretStore
- [appendix/phase4-multi-app-isolation.md](appendix/phase4-multi-app-isolation.md) — ASK456 details
