#-------------------------------------------------------------
# terragrunt.hcl
#
# - configure inputs for this layer (was identity.tfvars)
# - backend key comes from state.hcl (see root.hcl)
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  profile     = "terraform"
  environment = "lab"
  region      = "us-east-1"
  email       = "a.afinsky@gmail.com"
}
