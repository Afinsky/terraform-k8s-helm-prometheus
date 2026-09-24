locals {
  # Distinct from ../eks-cluster/state.hcl's "terraform.tfstate": both units
  # of an account share that account's bucket (account.hcl's state_bucket),
  # so the key has to differ.
  state_key = "eks-workloads.tfstate"
}
