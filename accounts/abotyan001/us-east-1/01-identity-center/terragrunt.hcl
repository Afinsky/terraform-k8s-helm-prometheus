#-------------------------------------------------------------
# terragrunt.hcl
#
# - wire up the modules/identity-center module and configure its inputs (was identity.tfvars)
# - backend key comes from state.hcl (see root.hcl)
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Local path, not a versioned/remote source: this module isn't published outside this
  # repo. Unlike modules/eks-cluster it isn't reused across accounts either (it defines the
  # Organization itself, applied from exactly one account) — just kept out of the unit
  # directory for consistency with the other modules.
  source = "${get_repo_root()}/modules/identity-center"
}

inputs = {
  profile     = "terraform"
  environment = "dev"
  region      = "us-east-1"
  email       = "a.afinsky@gmail.com"
}
