#-------------------------------------------------------------
# terragrunt.hcl
#
# - same modules/eks-cluster module as accounts/abotyan001/us-east-1/eks-cluster, applied
#   into the workloads-dev account instead
# - backend key comes from state.hcl (see root.hcl); bucket/profile/role come
#   from account.hcl (this account gets its own state bucket, reached via the
#   terraform -> terraform-management -> terraform-target profile chain)
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/eks-cluster"
}

# dns_zone_writer_role_arn/dns_zone_id/dns_zone_name come from
# 01-identity-center's own state, in the abotyan001 account - not this
# one. Cross-account is not an issue: `dependency` runs `terragrunt output`
# in 01-identity-center's own directory, under its own configured profile
# ("terraform"), not this account's credentials. See
# accounts/abotyan001/us-east-1/eks-cluster/terragrunt.hcl's identical
# dependency for the fuller rationale (this used to be a hardcoded literal
# in global.hcl).
dependency "identity_center" {
  config_path = "../../../abotyan001/us-east-1/01-identity-center"

  mock_outputs = {
    dns_zone_writer_role_arn = "arn:aws:iam::000000000000:role/mock-dns-zone-writer"
    dns_zone_id              = "MOCK00000000000000000"
    dns_zone_name            = "mock.example.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  # SSO profile for account_id 841775659851, role "devops-admin" — that
  # permission set is assigned org-wide by modules/identity-center/permission_sets.tf,
  # so no new IAM role/trust policy was needed for this account.
  profile     = "workloads-dev.devops-admin"
  environment = "dev"
  region      = "us-east-1"
  repo_root   = get_repo_root()

  dns_zone_writer_role_arn = dependency.identity_center.outputs.dns_zone_writer_role_arn
  dns_zone_id              = dependency.identity_center.outputs.dns_zone_id
  dns_zone_name            = dependency.identity_center.outputs.dns_zone_name

  # EKS public API endpoint is restricted to this IP.
  # Refresh it before applying if it's stale: curl -s https://checkip.amazonaws.com
  my_ip_cidr = "83.175.181.227/32"

  # Different range from abotyan001/eks-cluster's 10.30.0.0/16 — no peering between
  # these accounts, but keeping them non-overlapping costs nothing and avoids
  # surprises if that ever changes.
  vpc = {
    homelab = {
      cidr             = "10.40.0.0/16"
      azs              = ["us-east-1c", "us-east-1f"]
      private_subnets  = ["10.40.10.0/24", "10.40.11.0/24"]
      public_subnets   = ["10.40.20.0/24", "10.40.21.0/24"]
      database_subnets = ["10.40.30.0/24", "10.40.31.0/24"]
    }
  }
}
