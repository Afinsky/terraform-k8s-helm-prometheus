#---------------------------------------------------------------------------------------------------------------------
# root.hcl
#
# https://github.com/gruntwork-io/terragrunt
#
# - constrain terraform/terragrunt versions
# - consolidate global/account/region variables across terragrunt layers
# - configure the S3 state backend — bucket is auto-created by Terragrunt itself (--backend-bootstrap, baked
#   into every Makefile command). It's never a terraform resource anywhere: Terragrunt checks for it via
#   the AWS SDK and creates it (versioned, AES256-encrypted, public access blocked) if missing, idempotently,
#   outside of any terraform state.
#
# NOTE: there's no `generate "provider"` block here. `develop`'s kubernetes/helm providers are wired off
# live `module.eks` outputs, which Terragrunt can't template statically, so both `provider.tf` files stay
# hand-written and committed as-is.
#---------------------------------------------------------------------------------------------------------------------

terraform_version_constraint  = ">= 1.3.2"
terragrunt_version_constraint = ">= 0.80.0"

locals {
  global_vars  = read_terragrunt_config(find_in_parent_folders("global.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl", "does-not-exist.fallback"), { locals = {} })
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl", "does-not-exist.fallback"), { locals = {} })

  # each leaf layer carries its own state.hcl (sibling of its terragrunt.hcl) with the exact S3 key it already
  # used before Terragrunt adoption (not path_relative_to_include()-derived, so no state migration is needed)
  state_vars = read_terragrunt_config("state.hcl")

  project_name = local.global_vars.locals.project_name
  common_tags  = local.global_vars.locals.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Auto configure terraform state bucket
# ---------------------------------------------------------------------------------------------------------------------
remote_state {
  backend = "s3"

  config = {
    bucket         = "dev-me-terraform-state"
    key            = local.state_vars.locals.state_key
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true
    s3_bucket_tags = local.common_tags
    # the state bucket is only ever read/written by the "terraform" static IAM user, regardless of which
    # profile a given stack's own provider.tf assumes for managing its resources (see 01-identity-center/provider.tf)
    profile = "terraform"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# variables inherited by every layer that includes this file
# ---------------------------------------------------------------------------------------------------------------------
inputs = merge(
  local.global_vars.locals,
  local.account_vars.locals,
  local.region_vars.locals,
)
