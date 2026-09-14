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

inputs = {
  # SSO profile for account_id 841775659851, role "devops-admin" — that
  # permission set is assigned org-wide by modules/identity-center/permission_sets.tf,
  # so no new IAM role/trust policy was needed for this account.
  profile     = "workloads-dev-admin"
  environment = "dev"
  region      = "us-east-1"
  repo_root   = get_repo_root()

  # PLAT-101 Phase 3: EKS public API endpoint is restricted to this IP.
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
