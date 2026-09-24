#-------------------------------------------------------------
# terragrunt.hcl
#
# Unit template, not a live unit - never run terragrunt in this directory.
# Each workload account instantiates it from its own
# accounts/<alias>/us-east-1/terragrunt.stack.hcl, which `terragrunt stack
# generate` copies into that account's .terragrunt-stack/eks-cluster/ along
# with a terragrunt.values.hcl holding the account's `values` (read below as
# values.*). Everything account-specific belongs in those values, not here.
#
# - wire up the modules/eks-cluster module and configure its inputs
# - backend key comes from state.hcl (copied next to the generated unit, see
#   root.hcl); bucket/profile/role come from the account's account.hcl
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/eks-cluster"
}

# dns_zone_writer_role_arn/dns_zone_id/dns_zone_name come from
# identity-center's own state, in the abotyan001 account - not the one
# this unit applies into. Cross-account is not an issue: `dependency` runs
# `terragrunt output` in identity-center's own directory, under its own
# configured profile ("terraform"), not this account's credentials.
dependency "identity_center" {
  # Absolute, not relative: identity-center exists exactly once, in
  # abotyan001, whichever account's .terragrunt-stack/ this is generated into.
  # It's itself a generated unit, so abotyan001's stack must be generated too
  # (the Makefile and CI generate every account's stack, not just this one).
  config_path = "${get_repo_root()}/accounts/abotyan001/us-east-1/.terragrunt-stack/identity-center"

  # Lets `plan`/`validate` work before identity-center has ever been
  # applied - `apply` still requires real outputs, since only
  # "validate"/"plan"/"init" are in mock_outputs_allowed_terraform_commands.
  mock_outputs = {
    dns_zone_writer_role_arn = "arn:aws:iam::000000000000:role/mock-dns-zone-writer"
    dns_zone_id              = "MOCK00000000000000000"
    dns_zone_name            = "mock.example.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  profile     = values.profile
  environment = values.environment
  region      = "us-east-1"
  repo_root   = get_repo_root()

  dns_zone_writer_role_arn = dependency.identity_center.outputs.dns_zone_writer_role_arn
  dns_zone_id              = dependency.identity_center.outputs.dns_zone_id
  dns_zone_name            = dependency.identity_center.outputs.dns_zone_name

  # EKS public API endpoint is restricted to this IP - the operator's, same
  # for every account, so it lives here once rather than in each stack file.
  # Refresh it before applying if it's stale: curl -s https://checkip.amazonaws.com
  my_ip_cidr = "83.175.181.227/32"

  vpc = values.vpc
}
