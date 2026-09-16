#-------------------------------------------------------------
# terragrunt.hcl
#
# - wire up the modules/eks-cluster module and configure its inputs (was develop.tfvars,
#   before the module's rename to eks-cluster; the tflint fixture is eks-cluster.tfvars now)
# - backend key comes from state.hcl (see root.hcl)
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Local path, not a versioned/remote source: this module isn't published outside this
  # repo. It is reused, though — see accounts/workloads-dev/us-east-1/eks-cluster/terragrunt.hcl,
  # the same module applied into a different account.
  source = "${get_repo_root()}/modules/eks-cluster"
}

# dns_zone_writer_role_arn/dns_zone_id/dns_zone_name used to be hardcoded
# literals in global.hcl (a comment there said "update by hand if
# 01-identity-center is ever re-applied with a different zone/role") -
# switched to a live dependency instead, same as the eks_cluster dependency
# in eks-workloads/terragrunt.hcl. Cross-account is not an issue here:
# `dependency` runs `terragrunt output` in 01-identity-center's own
# directory, under its own configured profile ("terraform"), not this
# stack's - it doesn't need this account's credentials to read that state.
dependency "identity_center" {
  config_path = "../01-identity-center"

  # Lets `plan`/`validate` work before 01-identity-center has ever been
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
  profile     = "abotyan001-root.devops-admin"
  environment = "dev"
  region      = "us-east-1"
  repo_root   = get_repo_root()

  dns_zone_writer_role_arn = dependency.identity_center.outputs.dns_zone_writer_role_arn
  dns_zone_id              = dependency.identity_center.outputs.dns_zone_id
  dns_zone_name            = dependency.identity_center.outputs.dns_zone_name

  # EKS public API endpoint is restricted to this IP.
  # Refresh it before applying if it's stale: curl -s https://checkip.amazonaws.com
  my_ip_cidr = "83.175.181.227/32"

  vpc = {
    homelab = {
      cidr             = "10.30.0.0/16"
      azs              = ["us-east-1c", "us-east-1f"]
      private_subnets  = ["10.30.10.0/24", "10.30.11.0/24"]
      public_subnets   = ["10.30.20.0/24", "10.30.21.0/24"]
      database_subnets = ["10.30.30.0/24", "10.30.31.0/24"]
    }
  }
}
