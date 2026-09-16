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
  # Local path, same reasoning as accounts/abotyan001/us-east-1/eks-cluster/terragrunt.hcl —
  # this module isn't reused (it defines the Organization itself, applied from exactly
  # one account), just kept out of the layer directory for consistency with `eks-cluster`.
  source = "${get_repo_root()}/modules/identity-center"
}

inputs = {
  profile     = "terraform"
  environment = "dev"
  region      = "us-east-1"
  email       = "a.afinsky@gmail.com"
}
