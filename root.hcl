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

  # State lives in the SAME account this account.hcl describes — abotyan001's own state stays in its
  # historical central bucket, read directly as the "terraform" static IAM user (no override needed
  # there). A member account vended by 01-identity-center/accounts.tf gets its own bucket, created
  # inside itself: its account.hcl sets state_profile to "terraform-management" (a chained ~/.aws/config
  # profile: terraform-management assumed from terraform) and state_role_arn to that account's
  # terraform-target — the role account_access_stackset.tf auto-deploys into every member account,
  # trusting only terraform-management. That single extra assume-role hop is also what lets
  # `--backend-bootstrap` create the bucket itself inside the member account on first apply — no separate
  # bootstrap stack for it either.
  state_bucket   = try(local.account_vars.locals.state_bucket, "dev-me-terraform-state")
  state_profile  = try(local.account_vars.locals.state_profile, "terraform")
  state_role_arn = try(local.account_vars.locals.state_role_arn, null)
}

# ---------------------------------------------------------------------------------------------------------------------
# Auto configure terraform state bucket
# ---------------------------------------------------------------------------------------------------------------------
remote_state {
  backend = "s3"

  config = merge(
    {
      bucket         = local.state_bucket
      key            = local.state_vars.locals.state_key
      region         = "us-east-1"
      encrypt        = true
      use_lockfile   = true
      s3_bucket_tags = local.common_tags
      # base credentials: "terraform" for abotyan001 itself, or the chained "terraform-management"
      # ~/.aws/config profile when state_role_arn points at a member account's terraform-target
      profile = local.state_profile
    },
    local.state_role_arn == null ? {} : {
      assume_role = { role_arn = local.state_role_arn }
    }
  )

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
