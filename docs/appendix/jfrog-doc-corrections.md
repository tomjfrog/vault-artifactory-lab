# JFrog documentation corrections

Reference: [JFrog HashiCorp Integrations](https://docs.jfrog.com/integrations/docs/hashicorp-integrations)

Corrections vs outdated JFrog doc examples that conflict with the plugin README and this lab.

## Bootstrap and service identity

| Topic | Official guidance | Lab implementation |
|-------|-------------------|-------------------|
| Bootstrap token | Scoped token with **Admin** scope | `JFROG_ACCESS_TOKEN` in `.env` |
| Service identity | Dedicated user (e.g. `vault-admin`) | `ARTIFACTORY_USERNAME` in `.env.example` |
| Token rotation | Rotate after bootstrap so only Vault holds admin token | `setup-vault.sh` → `make admin` (includes rotate) |
| Min Artifactory for rotation | 7.42.1+ | Documented in [architecture.md](../architecture.md) |

## 1. Artifactory URL format

**Use the platform base URL only** — do not append `/artifactory`:

```bash
# Correct
url=https://YOUR-TENANT.jfrog.io

# Incorrect (appears in some JFrog doc examples)
url=https://artifactory.example.org/artifactory
```

## 2. Admin username note

Use a **dedicated admin-scoped service user** (e.g. `vault-admin`). The plugin supports **dynamic usernames** via the default template (`v-{role}-{random}`).

## 3. Static vs dynamic role usernames

Official examples use fixed usernames. Prefer **no static username** so each lease gets a unique identity and avoids lockout from stale tokens.

## 4. Develop section local URL typo

Some examples show `url=http://127.0.0.1:8200/artifactory` — that is the Vault address, not Artifactory. Ignore that example.

## Out of scope for this lab

- Jenkins / AppRole CI upload flows
- Terraform provider sections (Artifactory, Projects, Xray)
- User tokens (`artifactory/user_token/:username`)
- GitHub Actions OIDC to Vault

This lab validates **Kubernetes namespace + service account → ESO → prod image pull** only. See [setup-and-validation.md](../setup-and-validation.md).
