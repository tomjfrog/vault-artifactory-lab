# Vault policy for CMDB app ASK123 (JFrog project ask123).
# Apply with: vault policy write ask123-pull policies/ask123-pull.hcl

path "artifactory/token/ask123" {
  capabilities = ["read"]
}

path "artifactory/roles/ask123" {
  capabilities = ["read"]
}
