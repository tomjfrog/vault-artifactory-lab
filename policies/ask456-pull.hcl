# Vault policy for CMDB app ASK456 (JFrog project ask456).
# Apply with: vault policy write ask456-pull policies/ask456-pull.hcl

path "artifactory/token/ask456" {
  capabilities = ["read"]
}

path "artifactory/roles/ask456" {
  capabilities = ["read"]
}
