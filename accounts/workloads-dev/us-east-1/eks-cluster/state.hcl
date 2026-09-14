locals {
  # own bucket (account.hcl's state_bucket), no collision risk with other layers/accounts
  state_key = "terraform.tfstate"
}
