#-------------------------------------------------------------
# terragrunt.hcl
#
# This stack creates the S3 bucket every other layer stores its state in, so
# it deliberately does NOT `include { path = find_in_parent_folders("root.hcl") }` —
# doing so would point its own remote_state config at a bucket that doesn't
# exist yet. It keeps using Terraform's default local backend, same as
# before Terragrunt adoption. This file exists only to give it a consistent
# CLI alongside the other layers (e.g. `terragrunt run --all plan`).
#-------------------------------------------------------------

locals {
  # read directly, not via root.hcl's inputs merge (this stack doesn't include root.hcl — see above)
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

inputs = {
  profile        = "terraform"
  environment    = "dev"
  aws_account_id = local.account_vars.locals.aws_account_id
}
