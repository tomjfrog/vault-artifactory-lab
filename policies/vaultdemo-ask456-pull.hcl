# Vault policy for app ASK456 (project vaultdemo).
# Allows read of the ASK456 Artifactory token path only.
# Apply with: vault policy write vaultdemo-ask456-pull policies/vaultdemo-ask456-pull.hcl

path "artifactory/token/vaultdemo-ask456" {
  capabilities = ["read"]
}

path "artifactory/roles/vaultdemo-ask456" {
  capabilities = ["read"]
}
