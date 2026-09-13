#---------------------------------------------------------------------------------------------------------------------
# root.hcl
#
# https://github.com/gruntwork-io/terragrunt
#
# - constrain terraform/terragrunt versions
# - consolidate global/account/region variables across terragrunt layers
# - configure the S3 state backend (bucket already exists — created once by 00-bootstrap, not by Terragrunt)
#
# NOTE: there's no `generate "provider"` block here.
# `develop`'s kubernetes/helm providers are wired off live `module.eks` outputs, which Terragrunt can't template
# statically, so both `provider.tf` files stay hand-written and committed as-is.
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
    bucket       = "dev-me-terraform-state"
    key          = local.state_vars.locals.state_key
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
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

# ---------------------------------------------------------------------------------------------------------------------
# clean up hook
# ---------------------------------------------------------------------------------------------------------------------
terraform {
  before_hook "clean_asdf_from_modules" {
    commands = ["init", "plan", "apply", "destroy"]
    execute = [
      "bash", "-c",
      <<-EOF
      if [ -d ${get_terragrunt_dir()}/.terragrunt-cache ]; then
        find ${get_terragrunt_dir()}/.terragrunt-cache -type f -name .tool-versions -exec rm -f {} +
        find ${get_terragrunt_dir()}/.terragrunt-cache -type f -name aliased-providers.tf.json -exec rm -f {} +
      fi
      EOF
    ]
  }
}
