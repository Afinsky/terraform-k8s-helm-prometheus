locals {
  # preserved exactly from the pre-Terragrunt identity.conf so no state migration is needed
  # TODO: rename this to something more generic, like "identity-center" or "sso", and update the state file name accordingly
  state_key = "eks-access-lab/identity/terraform.tfstate"
}
