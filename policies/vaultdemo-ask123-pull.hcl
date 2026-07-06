# Vault policy for app ASK123 (project vaultdemo).
# Allows read of the per-project Artifactory token path only.
# Apply with: vault policy write vaultdemo-ask123-pull policies/vaultdemo-ask123-pull.hcl

path "artifactory/token/vaultdemo" {
  capabilities = ["read"]
}

path "artifactory/roles/vaultdemo" {
  capabilities = ["read"]
}
