#-------------------------------------------------------------
# terragrunt.stack.hcl
#
# workloads-dev's EKS pair, instantiated from the unit templates in units/.
# `terragrunt stack generate` expands this into .terragrunt-stack/eks-cluster/
# and .terragrunt-stack/eks-workloads/ next to this file - gitignored, never
# edited by hand. `make ACCOUNT=workloads-dev eks-cluster|eks-workloads ...`
# and `terragrunt run --all` both regenerate it before running.
#
# Everything account-specific lives here. To onboard another workload account,
# copy this file (plus account.hcl and region.hcl) and change the locals and
# the VPC ranges.
#-------------------------------------------------------------

locals {
  # SSO profile for account_id 841775659851, role "devops-admin" - that
  # permission set is assigned org-wide by modules/identity-center/permission_sets.tf,
  # so no new IAM role/trust policy was needed for this account.
  profile     = "workloads-dev.devops-admin"
  environment = "dev"
}

unit "eks-cluster" {
  source = "${get_repo_root()}/units/eks-cluster"
  path   = "eks-cluster"

  values = {
    profile     = local.profile
    environment = local.environment

    # Keep every account's range distinct (10.30.0.0/16 was the management
    # account's, before EKS moved out of it) - no peering between accounts
    # today, but non-overlapping ranges cost nothing and avoid surprises if
    # that ever changes.
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
}

unit "eks-workloads" {
  source = "${get_repo_root()}/units/eks-workloads"
  # must stay a sibling of eks-cluster: the unit's dependency is "../eks-cluster"
  path = "eks-workloads"

  values = {
    profile     = local.profile
    environment = local.environment
  }
}
