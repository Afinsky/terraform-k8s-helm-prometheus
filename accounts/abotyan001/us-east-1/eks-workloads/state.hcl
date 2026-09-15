locals {
  # distinct from eks-cluster/state.hcl's "terraform.tfstate" - same bucket
  # (root.hcl's state_bucket comes from account.hcl, shared by every layer
  # in this account), so the key has to differ.
  state_key = "eks-workloads.tfstate"
}
