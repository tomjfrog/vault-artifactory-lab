# Admin token bootstrap and rotation

How Phase 0 configures the JFrog Vault plugin’s Artifactory admin credential, why the lab rotates immediately after bootstrap, and what that means for day‑2 operations.

Related: [setup-and-validation.md — Phase 0](setup-and-validation.md#phase-0--plugin-and-vault-bootstrap), [follow-up-questions-response.md §5](../follow-up-questions-response.md#5-where-is-the-admin-token-saved-can-many-kubernetes-clusters-access-it), [plugin README — Configuration](https://github.com/jfrog/vault-plugin-secrets-artifactory#configuration).

---

## What happens at bootstrap

Phase 0 (`scripts/setup-vault.sh`) runs three steps in order:

```bash
vault write artifactory/config/admin \
  url="${JFROG_URL}" \
  access_token="${JFROG_ACCESS_TOKEN}"

vault read artifactory/config/admin

vault write -f artifactory/config/rotate

vault read artifactory/config/admin
```

| Step | Path | Effect |
|------|------|--------|
| 1 | `artifactory/config/admin` | Operator-supplied admin-scoped token from `.env` (`JFROG_ACCESS_TOKEN`) is stored in Vault (seal-wrapped). |
| 2 | `vault read artifactory/config/admin` | Returns **metadata only** — URL, username, scope, token id, SHA256 hash — not the raw token. |
| 3 | `artifactory/config/rotate` | Plugin mints a **new** admin token, stores it in Vault, sets `revoke_on_delete=true`, and **revokes the bootstrap token** in Artifactory. |

After rotation, the plugin uses only the token inside Vault to call Artifactory when issuing scoped workload tokens via `artifactory/token/{role}`.

---

## What rotation does (plugin behavior)

From the [plugin source](https://github.com/jfrog/vault-plugin-secrets-artifactory/blob/main/path_config_rotate.go), `config/rotate`:

1. Reads the current admin token from Vault storage.
2. Creates a new Artifactory access token with the same scope (default username `admin-vault-secrets-artifactory`).
3. Saves the new token to `artifactory/config/admin`.
4. Sets `revoke_on_delete=true` on the config.
5. Revokes the **previous** token in Artifactory.

Rotation is **optional but recommended** in the [plugin README](https://github.com/jfrog/vault-plugin-secrets-artifactory#configuration) so that only Vault holds the long-lived admin credential — not the operator’s bootstrap token in `.env` or CI secrets.

---

## Why rotate (benefits)

| Benefit | Explanation |
|---------|-------------|
| **Shorter human-held admin exposure** | The token you paste into `.env` is one-time bootstrap; it is revoked after rotate. |
| **Dedicated plugin identity** | Runtime admin token appears in Artifactory as a distinct user (e.g. `admin-vault-secrets-artifactory`) with a clear description. |
| **Non-expiring admin token (7.42.1+)** | Rotated tokens on supported Artifactory versions can be non-expiring even when bootstrap tokens were created with short TTLs — see [plugin admin token expiration notice](https://github.com/jfrog/vault-plugin-secrets-artifactory#admin-token-expiration-notice). |
| **Aligns with production practice** | Lab matches the pattern customers should use: bootstrap → rotate → discard bootstrap material. |

Workloads and ESO **never** receive this admin token. They authenticate via Kubernetes auth and policies such as `ask123-pull`, which allow `read` on `artifactory/token/ask123` only.

---

## Drawbacks and operational implications

### Bootstrap token in `.env` is immediately invalid

After `config/rotate`, `JFROG_ACCESS_TOKEN` in `.env` is **revoked in Artifactory**. Re-running Phase 0 with the same value fails:

```text
Token failed verification: revoked
```

**Mitigation:** Mint a fresh admin-scoped token before each re-bootstrap:

```bash
jf access-token-create \
  --server-id "${JFROG_SERVER_ID}" \
  --grant-admin \
  --description "vault-lab-bootstrap" \
  --expiry 86400 \
  --format json | jq -r .access_token
```

Update `JFROG_ACCESS_TOKEN` in `.env`, then re-run `./scripts/setup-vault.sh`.

### Re-bootstrap always needs a new break-glass token

This matters most in **Vault dev mode** (in-memory): stopping Vault wipes `artifactory/config/admin`. Phase 0 must run again with a **new** admin token in `.env`. The rotated runtime token cannot be read back from Vault.

### Admin credential is irrecoverable from Vault CLI

`vault read artifactory/config/admin` never returns the raw token. If Vault storage is lost and no separate Artifactory admin access exists, the plugin cannot issue tokens until someone with Artifactory admin rights re-runs bootstrap + rotate.

### `revoke_on_delete=true` after rotation

Deleting `artifactory/config/admin` (accidental teardown or misconfiguration) **revokes the plugin’s admin token in Artifactory**. No new scoped tokens are issued until config is restored.

### Partial failure on older Artifactory versions

The plugin README notes that on some versions (e.g. **7.39.10**), rotation may create the new token but **fail to revoke the old one** — leaving two valid admin tokens until cleaned up manually. Use **Artifactory 7.42.1+** for reliable non-expiring admin tokens and cleaner rotation.

### Bootstrap token TTL surprises

Tokens minted with short expiry (some scripts default to **1 hour**) must complete bootstrap + rotate before expiry. If bootstrap expires mid-run, rotate never runs and Phase 0 fails.

Check expiration after bootstrap (plugin v0.2.9+):

```bash
vault read artifactory/config/admin
```

If `exp` / `expires` fields are absent, the stored admin token has no Artifactory-side expiration.

### Operational and governance overhead

- Track the plugin’s Artifactory token identity in Access → Tokens.
- Document **break-glass**: who can mint new admin-scoped tokens independent of Vault.
- Old bootstrap tokens in password managers or runbooks are revoked — good for security, confusing if reused.

### Rotation does not eliminate admin blast radius

The rotated token is still **admin-scoped** inside Vault. Compromise of Vault storage or overly broad policies on `artifactory/config/admin` still affects all apps on that Artifactory instance. Rotation reduces **operator-held** admin exposure; it does not replace Vault policy hardening or Artifactory audit.

---

## When you might skip rotation

Skipping `vault write -f artifactory/config/rotate` leaves the bootstrap token valid in Artifactory — simpler for repeated local teardowns, but **worse security** (long-lived admin in `.env`). This lab **always rotates** to mirror production.

---

## Quick reference

| After bootstrap + rotate | Implication |
|--------------------------|-------------|
| `.env` `JFROG_ACCESS_TOKEN` | Revoked — one-time bootstrap only |
| Runtime admin token | Only inside Vault; not readable via CLI |
| Vault dev restart | Full Phase 0 + **new** bootstrap token required |
| Plugin identity in Artifactory | e.g. `admin-vault-secrets-artifactory` — monitor in token list |
| Workload / ESO access | Must **not** have policy on `artifactory/config/admin` |
| Break-glass | Platform team retains ability to mint new admin-scoped Artifactory tokens |

---

## See also

- [External references — JFrog Vault plugin](setup-and-validation.md#jfrog-platform-and-vault-plugin)
- [Plugin README — Admin token expiration](https://github.com/jfrog/vault-plugin-secrets-artifactory#admin-token-expiration-notice)
- [JFrog — Introduction to access tokens](https://jfrog.com/help/r/jfrog-platform-administration-documentation/introduction-to-access-tokens)
