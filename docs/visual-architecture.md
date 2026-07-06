# Visual architecture (Mermaid)

Visual reference for the Vault ↔ Artifactory lab: **entity relationships**, **setup order**, and **runtime flows**.

Validated on JFrog Cloud, local Vault dev, Rancher Desktop k3s, Phases 0–4.

| Diagram | Use when |
|---------|----------|
| [Entity relationship](#entity-relationship-diagram) | Understanding *what connects to what* (CMDB → group → repo → Vault → K8s) |
| [Setup sequence](#setup-order-sequence-diagram) | Provisioning a new app or reproducing the lab |
| [Runtime ESO sequence](#runtime-sequence-automated-eso-path) | Explaining the automated pull-credential chain |
| [Multi-app isolation](#multi-app-isolation) | Why ASK123 cannot pull ASK456 (and vice versa) |

Related: [setup-and-validation.md](setup-and-validation.md), [architecture.md](architecture.md).

---

## Key findings (lab-validated)

| Finding | Implication |
|---------|-------------|
| `artifactory/` is a **plugin secrets engine** | Dynamic token issue on read — **not** Vault KV |
| ESO Vault **SecretStore** is KV-only | Use **VaultDynamicSecret** + `ExternalSecret.dataFrom.generatorRef` for `artifactory/token/…` |
| Token path vs role path | **`artifactory/token/ask123`** issues credentials; **`artifactory/roles/ask123`** is config only |
| One `vault read` per Docker login | Username + `access_token` must come from the **same** response |
| Phase 1 scope | `setup-phase1-vault.sh` derives scope from `ASK_ID` |
| Vault from cluster | `http://host.docker.internal:8200` (Rancher Desktop) |
| Permission target create | `POST /access/api/v2/permissions` with `name` in body (not `POST …/permissions/{name}`) |
| Per-app isolation | Separate JFrog project + group + permission target + dev/prod repos + Vault role + policy + K8s auth role |

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
        string jfrog_project "ask123 or ask456"
    }

    ARTIFACTORY_GROUP {
        string name "AZU_ARTIFACTORY_ASK123"
    }

    PERMISSION_TARGET {
        string name "ask123-docker-prod-pull"
        string permission "READ"
    }

    PROD_DOCKER_REPO {
        string key "ask123-docker-prod-local"
        string env "PROD"
    }

    DOCKER_IMAGE {
        string name "ask-123-demo:1.0.0"
    }

    VAULT_SECRETS_ENGINE {
        string mount "artifactory"
        string type "plugin not KV"
    }

    VAULT_PLUGIN_ROLE {
        string name "ask123"
        string scope "applied-permissions/groups:..."
    }

    VAULT_TOKEN_PATH {
        string path "artifactory/token/ask123"
    }

    VAULT_POLICY {
        string name "ask123-pull"
    }

    VAULT_K8S_AUTH_ROLE {
        string name "ask123-workload"
        string mount "auth/kubernetes"
    }

    K8S_NAMESPACE {
        string name "ask123-ns"
    }

    K8S_SERVICE_ACCOUNT {
        string name "ask123-workload-sa"
    }

    VAULT_DYNAMIC_SECRET {
        string name "artifactory-ask123-token"
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

### Lab instances (two apps, two JFrog Projects)

```mermaid
flowchart TB
    subgraph ask123proj["JFrog Project ask123"]
        subgraph ask123["CMDB ASK123"]
            G1["Group AZU_ARTIFACTORY_ASK123"]
            P1["Perm ask123-docker-prod-pull"]
            D1["Repo ask123-docker-dev-local"]
            R1["Repo ask123-docker-prod-local"]
            I1["Image ask-123-demo:1.0.0"]
            G1 --> P1 --> R1 --> I1
        end
    end

    subgraph ask456proj["JFrog Project ask456"]
        subgraph ask456["CMDB ASK456"]
            G2["Group AZU_ARTIFACTORY_ASK456"]
            P2["Perm ask456-docker-prod-pull"]
            D2["Repo ask456-docker-dev-local"]
            R2["Repo ask456-docker-prod-local"]
            I2["Image ask-456-demo:1.0.0"]
            G2 --> P2 --> R2 --> I2
        end
    end

    subgraph vault["Vault dev"]
        VR1["role ask123"]
        VR2["role ask456"]
        VP1["policy ask123-pull"]
        VP2["policy ask456-pull"]
        VR1 --> VP1
        VR2 --> VP2
    end

    subgraph k8s["Kubernetes"]
        NS1["ask123-ns"]
        NS2["ask456-ns"]
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
    participant GH as GitHub Releases
    participant Vault
    participant JFrog as JFrog Platform
    participant K8s as Kubernetes
    participant ESO as External Secrets Operator

    rect rgb(240, 248, 255)
        Note over Op,Vault: Phase 0 — Plugin bootstrap
        Op->>GH: download-plugin.sh (darwin_arm64 / amd64)
        Op->>Vault: start-vault-dev.sh (dev server + plugin dir)
        Op->>Vault: register plugin, enable artifactory/
        Op->>Vault: artifactory/config/admin (URL + admin token)
    end

    rect rgb(255, 250, 240)
        Note over Op,JFrog: Phase 1a — Artifactory RBAC (ASK123, project ask123)
        Op->>JFrog: setup-phase1-artifactory.sh (project, group, dev+prod repos, permission)
        Op->>JFrog: Publish ask-123-demo:1.0.0 to dev + prod repos
    end

    rect rgb(240, 255, 240)
        Note over Op,Vault: Phase 1b — Vault role + policy
        Op->>Vault: policy write ask123-pull
        Op->>Vault: write artifactory/roles/ask123 (scope = ASK123 group)
    end

    rect rgb(255, 240, 255)
        Note over Op,K8s: Phase 2 — Kubernetes auth
        Op->>K8s: namespace ask123-ns, SA ask123-workload-sa
        Op->>K8s: SA vault-auth + auth-delegator (kube-system)
        Op->>Vault: enable auth/kubernetes, configure API + reviewer JWT
        Op->>Vault: role ask123-workload → policy ask123-pull
    end

    rect rgb(255, 255, 230)
        Note over Op,ESO: Phase 3 — ESO (ASK123 namespace)
        Op->>K8s: helm install external-secrets
        Op->>K8s: VaultDynamicSecret (GET artifactory/token/ask123)
        Op->>K8s: ExternalSecret → artifactory-pull (dockerconfigjson)
    end

    rect rgb(230, 245, 255)
        Note over Op,K8s: Phase 4 — Second app (ASK456, project ask456)
        Op->>JFrog: setup-phase4-artifactory.sh (project, group, dev+prod repos, permission)
        Op->>Vault: role ask456 + policy ask456-pull
        Op->>K8s: namespace ask456-ns + K8s auth role ask456-workload
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

    ESO->>K8sAPI: Request SA token for ask123-workload-sa
    K8sAPI-->>ESO: ServiceAccount JWT

    ESO->>Vault: auth/kubernetes/login (role ask123-workload, jwt)
    Vault->>K8sAPI: TokenReview (vault-auth SA)
    K8sAPI-->>Vault: SA identity confirmed
    Vault-->>ESO: Vault token (policy ask123-pull)

    ESO->>Vault: GET /v1/artifactory/token/ask123
    Vault->>Plugin: issue token (scope AZU_ARTIFACTORY_ASK123)
    Plugin->>Access: POST /access/api/v1/tokens
    Access-->>Plugin: username + access_token
    Plugin-->>ESO: data.username, data.access_token

    ESO->>ESO: Template kubernetes.io/dockerconfigjson
    ESO->>K8sAPI: Create/Update Secret artifactory-pull

    Note over Kubelet: Pod scheduled with imagePullSecrets

    Kubelet->>K8sAPI: Read Secret artifactory-pull
    Kubelet->>RT: docker pull ask123-docker-prod-local/ask-123-demo:1.0.0
    RT->>RT: Check group AZU_ARTIFACTORY_ASK123 READ on repo
    RT-->>Kubelet: Image layers
    Kubelet-->>Kubelet: Start container
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
    T123->>RT: pull ask123-docker-prod-local/ask-123-demo
    RT-->>T123: OK
    T123->>RT: pull ask456-docker-prod-local/ask-456-demo
    RT-->>T123: DENIED

    Note over T456: scope AZU_ARTIFACTORY_ASK456
    T456->>RT: pull ask456-docker-prod-local/ask-456-demo
    RT-->>T456: OK
    T456->>RT: pull ask123-docker-prod-local/ask-123-demo
    RT-->>T456: DENIED
```

```mermaid
flowchart LR
    subgraph vault_isolation["Vault policy boundary"]
        SA456["ask456-workload-sa<br/>ask456-ns"]
        AR456["auth role<br/>ask456-workload"]
        P456["policy<br/>ask456-pull"]
        TP456["artifactory/token/ask456"]
        SA456 --> AR456 --> P456 --> TP456
        TP123["artifactory/token/ask123"]
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
        CMDB1 --> VR1["Plugin role ask123"]
        VR1 --> S1["scope = group"]
        VR1 --> PATH1["token path artifactory/token/ask123"]
        POL1["Policy ask123-pull"] --> PATH1
    end

    subgraph L3["Layer 3 — Kubernetes"]
        SA1["SA ask123-workload-sa"] --> KAUTH1["K8s auth role"]
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
| 0 | `download-plugin.sh`, `start-vault-dev.sh`, `setup-vault.sh` | `vault read artifactory/config/admin` |
| 1a–1c | `setup-phase1-artifactory.sh`, `setup-phase1-vault.sh` | `docker pull` prod, `vault read artifactory/roles/ask123` |
| 1d | — | `demo-isolation.sh` (optional Layer 1) |
| 2 | `setup-kubernetes-auth.sh` | `demo-kubernetes-auth.sh` |
| 3 | `setup-eso.sh` | `demo-eso.sh` (primary) |
| 4 | `setup-phase4-artifactory.sh`, `setup-phase4-vault.sh` | `demo-isolation-multi-app.sh` |

---

## Related docs

- [setup-and-validation.md](setup-and-validation.md) — canonical runbook
