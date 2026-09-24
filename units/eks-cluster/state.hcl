locals {
  # Every workload account keeps state in its own bucket (account.hcl's
  # state_bucket), so this key only has to be unique among the units of one
  # account - hence one fixed value shared by every account. Distinct from
  # ../eks-workloads/state.hcl's key for the same reason.
  state_key = "terraform.tfstate"
}
