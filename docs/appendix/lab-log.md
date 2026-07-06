# Lab log

Historical chronology of lab build-out. **Canonical runbook:** [../setup-and-validation.md](../setup-and-validation.md).

This file is **customer-shareable** — keep sensitive details in `internal/` instead.

## Template

### YYYY-MM-DD — Title

**Goal:**

**Steps executed:**

1.

**Result:**

**Notes / follow-ups:**

---

## Entries

### 2026-06-22 — Lab repo created

**Goal:** Stand up a companion repo for Vault ↔ Artifactory lab development, separate from the plugin codebase.

**Steps executed:**

1. Created `~/code/vault-artifactory-lab`
2. Added multi-root Cursor workspace including plugin + lab repos
3. Scaffolded scripts, policies, and docs directories

**Result:** Repo ready for sandbox configuration and demo scripting.

**Notes / follow-ups:**

- [x] Provision JFrog Cloud sandbox
- [x] Create admin-scoped access token (dedicated service user)
- [x] Run `scripts/setup-vault.sh` against sandbox

### 2026-06-22 — Aligned demo with JFrog HashiCorp integration docs

**Goal:** Revise lab demo to match official JFrog integration guidance.

**Changes:**

1. Default CI scope → `applied-permissions/groups:automation`
2. Dynamic usernames (no static `example-service-jenkins`)
3. Added AppRole CI consumer flow (`setup-approle.sh`)
4. Added Artifactory token verification + lease revoke in `demo.sh`
5. Documented URL gotchas and outdated examples in `jfrog-integration-notes.md`

**Notes / follow-ups:**

- [ ] Create `automation` group + permission target in sandbox UI
- [ ] Re-run `./scripts/demo.sh` after Artifactory prep

### 2026-06-22 — Lab Docker assets on JFrog Project `vaultdemo`

**Goal:** Add a pull-verification Docker image hosted in a project-scoped local Docker repo.

**Provisioned via JFrog Experimental MCP:**

1. Project `vaultdemo` (Vault Demo)
2. Local Docker repository `vaultdemo-docker-local`
3. Image `lab-demo:1.0.0` built from `assets/Dockerfile.ask123` and pushed to Artifactory

**Documentation:** `docs/lab-provisioned-assets.md`, `assets/README.md`

### 2026-06-22 — Local K8s smoke test (manual imagePullSecret)

**Goal:** Validate Vault-issued Artifactory tokens work as Docker pull credentials in Rancher Desktop k3s.

**Steps executed:**

1. Created namespace `vaultdemo-ns`
2. Issued token via `vault read artifactory/token/jenkins`
3. Created `docker-registry` secret `artifactory-pull`
4. Ran pod `lab-demo` pulling `vaultdemo-docker-local/lab-demo:1.0.0`

**Result:** Pod `Running`; log output `Successful Image Pull from Artifactory`.

**Proves:** Vault plugin token → Artifactory registry auth → k8s OCI pull → running container.

**Not yet proven at this stage:** ESO, Kubernetes auth, ASK123 prod path (completed in later entries).

**Documentation:** [docs/local-k8s-smoke-test.md](local-k8s-smoke-test.md)

### 2026-06-22 — Phase 1 MCP provisioning (ASK123)

**Goal:** Provision Phase 1 Artifactory resources via JFrog Experimental MCP.

**MCP created:**

1. Repository `vaultdemo-docker-prod-local` (PROD Docker, project `vaultdemo`)

**MCP blocked then resolved:**

1. Permission target `vaultdemo-ask123-prod-pull` — first attempt failed (group missing); **created on retry** after group `AZU_ARTIFACTORY_ASK123` was added via Access API

**Manual (Access API):**

1. Group `AZU_ARTIFACTORY_ASK123` — `POST /access/api/v2/groups` via `jf api`

**Documentation:** [docs/phase1-provisioning.md](phase1-provisioning.md)

### 2026-06-22 — Prod image published (dev → prod)

**Goal:** Place `lab-demo:1.0.0` in the production Docker repo for ASK123 pull tests.

**Steps executed:**

1. `jf rt docker-promote lab-demo vaultdemo-docker-local vaultdemo-docker-prod-local --source-tag=1.0.0 --copy=true`
2. Verified via `docker pull YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/lab-demo:1.0.0`

**Result:** Image available in prod repo. Digest matches dev: `sha256:c3db0fcd7714...`.

**Notes:**

- Direct publish to prod (`DOCKER_REPO=vaultdemo-docker-prod-local ./assets/publish.sh`) is equivalent for this lab.
- Promote mirrors customer CI pipelines (build to dev, promote to prod).
- Storage API path is `list.manifest.json`, not `manifest.json`.

### 2026-06-22 — Phase 1 Vault configuration (role `vaultdemo`)

**Goal:** Map Vault role `vaultdemo` to Artifactory group `AZU_ARTIFACTORY_ASK123`.

**Steps executed:**

1. `./scripts/setup-phase1-vault.sh` — policy `vaultdemo-ask123-pull`, role `vaultdemo`
2. Fixed script to ignore `.env` `ARTIFACTORY_SCOPE=readers` (was overriding ASK123 scope)

**Result:** `vault read artifactory/roles/vaultdemo` shows `applied-permissions/groups:AZU_ARTIFACTORY_ASK123`.

**Documentation:** [setup-and-validation.md](setup-and-validation.md)

### 2026-06-22 — Phase 1 isolation tests passed

**Goal:** Prove ASK123 token pulls prod only; dev repo denied.

**Steps executed:**

1. `./scripts/demo-isolation.sh` (after fixing single-token `vault read` and authenticated docker pull)

**Result:**

- PASS: prod pull `vaultdemo-docker-prod-local/lab-demo:1.0.0`
- PASS: dev pull denied `vaultdemo-docker-local/lab-demo:1.0.0`

**Issues fixed during testing:**

| Issue | Root cause | Fix |
|-------|------------|-----|
| Scope `readers` on role | `.env` `ARTIFACTORY_SCOPE` overrode Phase 1 setup | `setup-phase1-vault.sh` uses `PHASE1_SCOPE` from `ASK_ID` |
| Docker `Wrong username was used` | Three separate `vault read` calls → mismatched username/token | Single `vault read -format=json` in `demo-isolation.sh` |
| False positive prod pull | Cached Docker admin creds without `docker login` | Script logs out, removes local images, logs in with Vault token |
| Storage API 403 | Wrong path / auth for Docker manifests | Use `docker pull` for validation |

### 2026-06-22 — K8s smoke test (ASK123 prod path)

**Goal:** Validate Vault `vaultdemo` token → `imagePullSecret` → prod image → running pod.

**Steps executed:**

1. Single `vault read -format=json artifactory/token/vaultdemo`
2. Secret `artifactory-pull` in namespace `vaultdemo-ns`
3. Pod `lab-demo` with image `YOUR-TENANT.jfrog.io/vaultdemo-docker-prod-local/lab-demo:1.0.0`

**Result:** Pod `Running`; log `Successful Image Pull from Artifactory`.

**Proves:** Full Phase 1 customer pull path on local k3s (manual secret; no ESO/K8s auth yet).

**Documentation:** [local-k8s-smoke-test.md](local-k8s-smoke-test.md) updated for prod path.

### 2026-06-22 — Phase 1 complete; documentation consolidated

**Goal:** Record provisioned assets, setup order, and validation checklist.

**Documentation added/updated:**

1. [setup-and-validation.md](setup-and-validation.md) — canonical setup order and validation checklist
2. [lab-provisioned-assets.md](lab-provisioned-assets.md) — full inventory (JFrog + Vault + K8s)
3. [phase1-provisioning.md](phase1-provisioning.md) — Phase 1 status complete
4. [local-k8s-smoke-test.md](local-k8s-smoke-test.md) — `vaultdemo` + prod repo procedure

**Phase 1 status:** Complete.

**Next phases:**

- [x] Phase 2: Vault Kubernetes auth (`workload-sa` → `vaultdemo-ask123-pull`)
- [x] Phase 3: External Secrets Operator — [phase3-eso-plan.md](phase3-eso-plan.md)
- [x] Phase 4: Multi-app isolation — [phase4-multi-app-isolation.md](phase4-multi-app-isolation.md)

### 2026-07-06 — Phase 3 External Secrets Operator

**Goal:** ESO syncs `artifactory/token/vaultdemo` → `kubernetes.io/dockerconfigjson` → prod image pull without manual `vault read`.

**Steps executed:**

1. Installed ESO (Helm, namespace `external-secrets`)
2. Applied `VaultDynamicSecret` + `ExternalSecret` in `vaultdemo-ns`
3. `./scripts/demo-eso.sh` — validation

**Result:**

- PASS: ExternalSecret `artifactory-pull` Ready
- PASS: Pod `lab-demo-eso` Running on prod image; log `Successful Image Pull from Artifactory`

**Notes:**

- VaultDynamicSecret GET `/artifactory/token/vaultdemo` (not KV SecretStore)
- Vault URL from cluster: `http://host.docker.internal:8200`
- Refreshed revoked plugin admin token before validation (`vault write artifactory/config/admin`)

**Documentation:** [phase3-eso-plan.md](phase3-eso-plan.md), `k8s/eso/`, `scripts/setup-eso.sh`, `scripts/demo-eso.sh`

### 2026-07-06 — Phase 4 multi-app isolation (ASK456)

**Goal:** Second CMDB app with separate group, prod repo, Vault role; cross-app pull denial.

**Steps executed:**

1. `./scripts/setup-phase4-artifactory.sh` — group `AZU_ARTIFACTORY_ASK456`, repo `vaultdemo-docker-ask456-prod-local`, image `lab-demo-ask456:1.0.0`
2. `./scripts/setup-phase4-vault.sh` — role `vaultdemo-ask456`, policy, K8s auth in `vaultdemo-ask456-ns`
3. `./scripts/demo-isolation-multi-app.sh` — cross-app validation

**Result:**

- PASS: ASK123 pulls own prod repo; denied on ASK456 prod repo
- PASS: ASK456 pulls own prod repo; denied on ASK123 prod repo
- PASS: ASK456 K8s auth reads `artifactory/token/vaultdemo-ask456` only

**Documentation:** [phase4-multi-app-isolation.md](phase4-multi-app-isolation.md)

### 2026-07-06 — Visual architecture documentation

**Goal:** Document complex entity interactions across CMDB apps, Artifactory RBAC, Vault, Kubernetes, and ESO; provide Mermaid ERD and sequence diagrams for customer-facing explanation.

**Deliverables:**

1. [visual-architecture.md](visual-architecture.md) — entity relationship diagram, setup order sequence, ESO runtime sequence, manual Phase 1d sequence, multi-app isolation
2. Updated cross-links in `architecture.md`, `setup-and-validation.md`, `lab-provisioned-assets.md`, phase docs, README

**Key model:** Three binding layers per CMDB app — (1) Artifactory group → permission → prod repo, (2) Vault plugin role → policy → token path, (3) K8s SA → auth role → ESO → pull secret → pod.

**Documentation:** [visual-architecture.md](visual-architecture.md)

### 2026-06-22 — Phase 2 Vault Kubernetes auth

**Goal:** Workload service account authenticates to Vault without root token; read `artifactory/token/vaultdemo`.

**Steps executed:**

1. `./scripts/setup-kubernetes-auth.sh` — `workload-sa`, `kube-system/vault-auth`, `auth/kubernetes`, role `vaultdemo-workload`
2. `./scripts/demo-kubernetes-auth.sh` — validation

**Result:**

- PASS: SA JWT → Vault login with policy `vaultdemo-ask123-pull`
- PASS: Workload Vault token reads `artifactory/token/vaultdemo` (scope `AZU_ARTIFACTORY_ASK123`)
- PASS: `artifactory/config/admin` denied for workload token

**Proves:** K8s service account → Vault policy → plugin token path (customer SA mapping question).

**Documentation:** [phase2-kubernetes-auth.md](phase2-kubernetes-auth.md), [phase2-kubernetes-auth-notes.md](phase2-kubernetes-auth-notes.md), `scripts/setup-kubernetes-auth.sh`, `scripts/demo-kubernetes-auth.sh`

### 2026-06-22 — Phase 3 ESO integration documented (pre-implementation)

**Goal:** Clarify ESO + artifactory plugin integration before building Phase 3.

**Findings:**

1. `artifactory/` is a custom Vault **secrets engine** (plugin), not KV
2. ESO Vault **SecretStore** provider supports KV only
3. Planned approach: **VaultDynamicSecret** generator + `ExternalSecret.dataFrom.generatorRef`
4. Customer `remoteRef.key` should target `artifactory/token/vaultdemo` (token path), not `artifactory/roles/…`

**Documentation:** [phase3-eso-plan.md](phase3-eso-plan.md), [phase3-eso-notes.md](phase3-eso-notes.md) (customer Q&A in phase3-eso-plan, not in `internal/customer-requirements.md`)
