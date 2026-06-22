# Lab log

Chronological record of lab build-out: decisions, executed steps, and outcomes.
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

- [ ] Provision JFrog Cloud sandbox
- [ ] Create admin-scoped access token
- [ ] Run `scripts/setup-vault.sh` against sandbox
