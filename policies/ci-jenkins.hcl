# Vault policy for CI systems reading the jenkins Artifactory role.
# Apply with: vault policy write ci-jenkins policies/ci-jenkins.hcl

path "artifactory/token/jenkins" {
  capabilities = ["read"]
}

path "artifactory/roles/jenkins" {
  capabilities = ["read"]
}
