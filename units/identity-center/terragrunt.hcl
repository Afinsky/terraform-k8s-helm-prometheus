#-------------------------------------------------------------
# terragrunt.hcl
#
# Unit template, not a live unit - never run terragrunt in this directory.
# Instantiated exactly once, by accounts/abotyan001/us-east-1/terragrunt.stack.hcl
# (the management account): it defines the Organization itself, so unlike
# ../eks-cluster it's never reused across accounts - it's a stack unit purely
# so every layer in this repo is shaped the same way.
#
# - wire up the modules/identity-center module and configure its inputs (was identity.tfvars)
# - backend key comes from state.hcl (copied next to the generated unit, see root.hcl)
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Local path, not a versioned/remote source: this module isn't published outside this repo.
  source = "${get_repo_root()}/modules/identity-center"
}

inputs = {
  # Always the static "terraform" IAM user, never a stack value: this unit
  # defines the devops-admin permission set, and applying it under its own
  # not-yet-revocable STS token risks a self-lockout (see provider.tf).
  profile     = "terraform"
  environment = values.environment
  region      = "us-east-1"
  email       = values.email
}
